-- Inpatient movement integrity: make a ward-bed transfer an atomic, auditable state change.
-- The workflow owns canonical ward_beds state and keeps the legacy admissions ward/bed
-- projection synchronized. It also supports admitted-but-awaiting-bed placement by allowing
-- a NULL source bed.
CREATE TABLE IF NOT EXISTS public.inpatient_bed_movements (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id UUID NOT NULL REFERENCES public.patients(id) ON DELETE CASCADE,
  admission_id UUID NOT NULL REFERENCES public.admissions(id) ON DELETE CASCADE,
  movement_type TEXT NOT NULL CHECK (movement_type IN ('placement','transfer')),
  source_bed_id UUID REFERENCES public.ward_beds(id) ON DELETE SET NULL,
  destination_bed_id UUID NOT NULL REFERENCES public.ward_beds(id) ON DELETE RESTRICT,
  reason TEXT,
  notes TEXT,
  moved_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  moved_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_inpatient_bed_movements_patient_time
  ON public.inpatient_bed_movements(patient_id, moved_at DESC);
CREATE INDEX IF NOT EXISTS idx_inpatient_bed_movements_admission_time
  ON public.inpatient_bed_movements(admission_id, moved_at DESC);
CREATE INDEX IF NOT EXISTS idx_inpatient_bed_movements_destination
  ON public.inpatient_bed_movements(destination_bed_id, moved_at DESC);

ALTER TABLE public.inpatient_bed_movements ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "inpatient bed movements clinical read" ON public.inpatient_bed_movements;
CREATE POLICY "inpatient bed movements clinical read"
  ON public.inpatient_bed_movements
  FOR SELECT TO authenticated
  USING (
    public.has_role(auth.uid(),'admin')
    OR public.has_role(auth.uid(),'practitioner')
    OR public.has_role(auth.uid(),'nurse')
    OR public.has_role(auth.uid(),'midwife')
    OR public.has_role(auth.uid(),'specialist_nurse')
  );

REVOKE INSERT, UPDATE, DELETE ON public.inpatient_bed_movements FROM authenticated;

CREATE OR REPLACE FUNCTION public.transfer_patient_ward_bed_workflow(
  _patient_id UUID,
  _admission_id UUID,
  _destination_bed_id UUID,
  _source_bed_id UUID DEFAULT NULL,
  _reason TEXT DEFAULT NULL,
  _notes TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $$
DECLARE
  uid UUID := auth.uid();
  v_admission public.admissions%ROWTYPE;
  v_source public.ward_beds%ROWTYPE;
  v_destination public.ward_beds%ROWTYPE;
  v_source_count INTEGER;
  v_movement_id UUID;
  v_transition_id UUID;
  v_movement_type TEXT;
  v_destination_label TEXT;
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF NOT (
    public.has_role(uid,'admin')
    OR public.has_role(uid,'practitioner')
    OR public.has_role(uid,'nurse')
    OR public.has_role(uid,'midwife')
    OR public.has_role(uid,'specialist_nurse')
  ) THEN
    RAISE EXCEPTION 'Inpatient movement is not permitted';
  END IF;

  IF _patient_id IS NULL OR _admission_id IS NULL OR _destination_bed_id IS NULL THEN
    RAISE EXCEPTION 'Patient, admission and destination bed are required';
  END IF;

  PERFORM pg_advisory_xact_lock(pg_catalog.hashtextextended(_patient_id::text, 0));

  SELECT *
    INTO v_admission
  FROM public.admissions
  WHERE id = _admission_id
    AND patient_id = _patient_id
  FOR UPDATE;

  IF v_admission.id IS NULL THEN
    RAISE EXCEPTION 'Active admission not found for patient';
  END IF;

  IF v_admission.status <> 'admitted' THEN
    RAISE EXCEPTION 'Admission is not active';
  END IF;

  SELECT *
    INTO v_destination
  FROM public.ward_beds
  WHERE id = _destination_bed_id
  FOR UPDATE;

  IF v_destination.id IS NULL THEN
    RAISE EXCEPTION 'Destination bed not found';
  END IF;

  IF v_destination.status <> 'available' OR v_destination.patient_id IS NOT NULL THEN
    RAISE EXCEPTION 'Destination bed is not available';
  END IF;

  IF _source_bed_id IS NOT NULL AND _source_bed_id = _destination_bed_id THEN
    RAISE EXCEPTION 'Source and destination beds must differ';
  END IF;

  SELECT count(*)
    INTO v_source_count
  FROM public.ward_beds
  WHERE patient_id = _patient_id
    AND status = 'occupied';

  IF _source_bed_id IS NULL THEN
    IF v_source_count > 1 THEN
      RAISE EXCEPTION 'Patient has multiple occupied ward beds';
    END IF;

    IF v_source_count = 1 THEN
      SELECT *
        INTO v_source
      FROM public.ward_beds
      WHERE patient_id = _patient_id
        AND status = 'occupied'
        AND admission_id = _admission_id
      FOR UPDATE;

      IF v_source.id IS NULL THEN
        RAISE EXCEPTION 'Current occupied bed does not match the admission';
      END IF;
    END IF;
  ELSE
    SELECT *
      INTO v_source
    FROM public.ward_beds
    WHERE id = _source_bed_id
    FOR UPDATE;

    IF v_source.id IS NULL THEN
      RAISE EXCEPTION 'Source bed not found';
    END IF;

    IF v_source.patient_id IS DISTINCT FROM _patient_id OR v_source.admission_id IS DISTINCT FROM _admission_id OR v_source.status <> 'occupied' THEN
      RAISE EXCEPTION 'Source bed is not occupied by this admitted patient';
    END IF;
  END IF;

  IF v_source.id IS NOT NULL THEN
    UPDATE public.ward_beds
    SET patient_id = NULL,
        admission_id = NULL,
        status = 'available',
        released_at = now(),
        updated_at = now()
    WHERE id = v_source.id;
    v_movement_type := 'transfer';
  ELSE
    v_movement_type := 'placement';
  END IF;

  UPDATE public.ward_beds
  SET patient_id = _patient_id,
      admission_id = _admission_id,
      status = 'occupied',
      occupied_at = now(),
      released_at = NULL,
      updated_at = now()
  WHERE id = v_destination.id;

  SELECT wu.name || ' / ' || v_destination.bed_number
    INTO v_destination_label
  FROM public.ward_units wu
  WHERE wu.id = v_destination.ward_id;

  IF v_destination_label IS NULL THEN
    v_destination_label := v_destination.bed_number;
  END IF;

  UPDATE public.admissions
  SET ward = (
        SELECT wu.name
        FROM public.ward_units wu
        WHERE wu.id = v_destination.ward_id
      ),
      bed = v_destination.bed_number,
      updated_at = now()
  WHERE id = v_admission.id;

  INSERT INTO public.inpatient_bed_movements (
    patient_id,
    admission_id,
    movement_type,
    source_bed_id,
    destination_bed_id,
    reason,
    notes,
    moved_by
  )
  VALUES (
    _patient_id,
    _admission_id,
    v_movement_type,
    v_source.id,
    v_destination.id,
    NULLIF(pg_catalog.btrim(_reason), ''),
    NULLIF(pg_catalog.btrim(_notes), ''),
    uid
  )
  RETURNING id INTO v_movement_id;

  INSERT INTO public.care_transitions (
    patient_id,
    admission_id,
    transition_type,
    status,
    destination,
    summary,
    responsible_officer,
    completed_at
  )
  VALUES (
    _patient_id,
    _admission_id,
    'transfer',
    'completed',
    v_destination_label,
    COALESCE(
      NULLIF(pg_catalog.btrim(_reason), ''),
      CASE
        WHEN v_movement_type = 'placement' THEN 'Patient placed in an inpatient bed.'
        ELSE 'Patient transferred to a new inpatient bed.'
      END
    ),
    uid,
    now()
  )
  RETURNING id INTO v_transition_id;

  PERFORM public.record_system_audit(
    CASE WHEN v_movement_type = 'placement'
      THEN 'inpatient_bed_placed'
      ELSE 'inpatient_bed_transferred'
    END,
    'inpatient',
    'inpatient_bed_movement',
    v_movement_id,
    'info',
    pg_catalog.jsonb_build_object(
      'patient_id', _patient_id,
      'admission_id', _admission_id,
      'source_bed_id', v_source.id,
      'destination_bed_id', v_destination.id,
      'destination', v_destination_label,
      'transition_id', v_transition_id
    )
  );

  RETURN pg_catalog.jsonb_build_object(
    'movement_id', v_movement_id,
    'transition_id', v_transition_id,
    'movement_type', v_movement_type,
    'source_bed_id', v_source.id,
    'destination_bed_id', v_destination.id,
    'destination', v_destination_label,
    'status', 'completed'
  );
END;
$$;

REVOKE ALL ON FUNCTION public.transfer_patient_ward_bed_workflow(UUID,UUID,UUID,UUID,TEXT,TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.transfer_patient_ward_bed_workflow(UUID,UUID,UUID,UUID,TEXT,TEXT) TO authenticated;

-- Preserve the legacy assignment entry point, but route every patient placement
-- through the canonical atomic movement workflow so direct bed assignment cannot
-- bypass movement history, admission projection sync, or audit logging.
CREATE OR REPLACE FUNCTION public.assign_ward_bed(
  _bed_id UUID,
  _patient_id UUID,
  _admission_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $$
DECLARE
  uid UUID := auth.uid();
  v_admission_id UUID := _admission_id;
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF NOT (
    public.has_role(uid,'admin')
    OR public.has_role(uid,'nurse')
    OR public.has_role(uid,'specialist_nurse')
  ) THEN
    RAISE EXCEPTION 'Nursing role required';
  END IF;

  IF _bed_id IS NULL OR _patient_id IS NULL THEN
    RAISE EXCEPTION 'Bed and patient are required';
  END IF;

  IF v_admission_id IS NULL THEN
    SELECT a.id
      INTO v_admission_id
    FROM public.admissions a
    WHERE a.patient_id = _patient_id
      AND a.status = 'admitted'
    ORDER BY a.admitted_at DESC NULLS LAST
    LIMIT 1;
  END IF;

  IF v_admission_id IS NULL THEN
    RAISE EXCEPTION 'Active admission not found for patient';
  END IF;

  RETURN public.transfer_patient_ward_bed_workflow(
    _patient_id,
    v_admission_id,
    _bed_id,
    NULL,
    NULL,
    NULL
  );
END;
$$;

REVOKE ALL ON FUNCTION public.assign_ward_bed(UUID,UUID,UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.assign_ward_bed(UUID,UUID,UUID) TO authenticated;


-- Prevent the legacy release entry point from orphaning an active admission.
-- Active admitted patients must move through the canonical placement/transfer
-- workflow or the admission/discharge workflow that owns the bed lifecycle.
CREATE OR REPLACE FUNCTION public.release_ward_bed(
  _bed_id UUID,
  _notes TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $$
DECLARE
  uid UUID := auth.uid();
  v_bed public.ward_beds%ROWTYPE;
  v_admission public.admissions%ROWTYPE;
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF NOT (
    public.has_role(uid,'admin')
    OR public.has_role(uid,'nurse')
    OR public.has_role(uid,'specialist_nurse')
  ) THEN
    RAISE EXCEPTION 'Nursing role required';
  END IF;

  SELECT *
    INTO v_bed
  FROM public.ward_beds
  WHERE id = _bed_id
  FOR UPDATE;

  IF v_bed.id IS NULL OR v_bed.status <> 'occupied' THEN
    RAISE EXCEPTION 'Occupied bed not found';
  END IF;

  IF v_bed.admission_id IS NOT NULL THEN
    SELECT *
      INTO v_admission
    FROM public.admissions
    WHERE id = v_bed.admission_id
    FOR UPDATE;

    IF v_admission.id IS NOT NULL AND v_admission.status = 'admitted' THEN
      RAISE EXCEPTION 'Active admitted patients must use the inpatient movement or discharge workflow';
    END IF;
  END IF;

  UPDATE public.ward_beds
  SET patient_id = NULL,
      admission_id = NULL,
      status = 'cleaning',
      released_at = now(),
      notes = COALESCE(NULLIF(pg_catalog.btrim(_notes), ''), notes),
      updated_at = now()
  WHERE id = v_bed.id;

  RETURN pg_catalog.jsonb_build_object(
    'bed_id', v_bed.id,
    'status', 'cleaning',
    'released_patient_id', v_bed.patient_id,
    'released_admission_id', v_bed.admission_id
  );
END;
$$;

REVOKE ALL ON FUNCTION public.release_ward_bed(UUID,TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.release_ward_bed(UUID,TEXT) TO authenticated;


-- Make discharge the canonical owner of the occupied-bed -> cleaning transition.
-- This prevents a successful discharge from leaving a stale occupied bed and
-- keeps the admission lock, bed lock, billing handoff and audit event atomic.
CREATE OR REPLACE FUNCTION public.discharge_admission_workflow(
  _admission_id UUID,
  _summary TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $$
DECLARE
  uid UUID := auth.uid();
  v_admission public.admissions%ROWTYPE;
  v_bed public.ward_beds%ROWTYPE;
  v_occupied_count INTEGER;
  v_patient_name TEXT;
  v_patient_code TEXT;
  v_notification_id UUID;
  v_discharged_at TIMESTAMPTZ;
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF NOT (
    public.has_role(uid,'admin')
    OR public.has_role(uid,'practitioner')
    OR public.has_role(uid,'nurse')
    OR public.has_role(uid,'midwife')
  ) THEN
    RAISE EXCEPTION 'Admission discharge is not permitted';
  END IF;

  SELECT *
    INTO v_admission
  FROM public.admissions
  WHERE id = _admission_id
  FOR UPDATE;

  IF v_admission.id IS NULL THEN
    RAISE EXCEPTION 'Admission not found';
  END IF;

  IF v_admission.status = 'discharged' THEN
    PERFORM pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(v_admission.patient_id::text, 0)
    );

    SELECT count(*)
      INTO v_occupied_count
    FROM public.ward_beds
    WHERE patient_id = v_admission.patient_id
      AND status = 'occupied';

    IF v_occupied_count > 1 THEN
      RAISE EXCEPTION 'Patient has multiple occupied ward beds';
    END IF;

    IF v_occupied_count = 1 THEN
      SELECT *
        INTO v_bed
      FROM public.ward_beds
      WHERE patient_id = v_admission.patient_id
        AND admission_id = v_admission.id
        AND status = 'occupied'
      FOR UPDATE;

      IF v_bed.id IS NULL THEN
        RAISE EXCEPTION 'Discharged admission has an occupied bed with mismatched ownership';
      END IF;

      UPDATE public.ward_beds
      SET patient_id = NULL,
          admission_id = NULL,
          status = 'cleaning',
          released_at = COALESCE(released_at, now()),
          notes = COALESCE(notes, 'Released while reconciling discharged admission.'),
          updated_at = now()
      WHERE id = v_bed.id;
    END IF;

    SELECT id INTO v_notification_id
    FROM public.notifications
    WHERE related_entity_id = v_admission.id
      AND category = 'payment'
      AND recipient_role = 'accountant'
      AND metadata->>'workflow' = 'discharge_billing_handoff'
    ORDER BY created_at DESC
    LIMIT 1;

    RETURN pg_catalog.jsonb_build_object(
      'admission_id', v_admission.id,
      'patient_id', v_admission.patient_id,
      'status', 'discharged',
      'bed_id', v_bed.id,
      'bed_status', CASE WHEN v_bed.id IS NULL THEN NULL ELSE 'cleaning' END,
      'billing_handoff', 'pending',
      'existing', TRUE,
      'notification_id', v_notification_id
    );
  END IF;

  IF v_admission.status <> 'admitted' THEN
    RAISE EXCEPTION 'Admission is not active';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_admission.patient_id::text, 0)
  );

  SELECT count(*)
    INTO v_occupied_count
  FROM public.ward_beds
  WHERE patient_id = v_admission.patient_id
    AND status = 'occupied';

  IF v_occupied_count > 1 THEN
    RAISE EXCEPTION 'Patient has multiple occupied ward beds';
  END IF;

  IF v_occupied_count = 1 THEN
    SELECT *
      INTO v_bed
    FROM public.ward_beds
    WHERE patient_id = v_admission.patient_id
      AND admission_id = v_admission.id
      AND status = 'occupied'
    FOR UPDATE;

    IF v_bed.id IS NULL THEN
      RAISE EXCEPTION 'Occupied bed does not match the admission';
    END IF;
  END IF;

  v_discharged_at := now();

  UPDATE public.admissions
  SET status = 'discharged',
      discharged_at = v_discharged_at,
      discharge_summary = COALESCE(
        NULLIF(pg_catalog.btrim(_summary), ''),
        'Discharged from inpatient admission.'
      ),
      updated_at = v_discharged_at
  WHERE id = v_admission.id;

  IF v_bed.id IS NOT NULL THEN
    UPDATE public.ward_beds
    SET patient_id = NULL,
        admission_id = NULL,
        status = 'cleaning',
        released_at = v_discharged_at,
        notes = COALESCE(notes, 'Released on inpatient discharge.'),
        updated_at = v_discharged_at
    WHERE id = v_bed.id;
  END IF;

  SELECT concat_ws(' ', first_name, last_name), patient_code
    INTO v_patient_name, v_patient_code
  FROM public.patients
  WHERE id = v_admission.patient_id;

  SELECT id INTO v_notification_id
  FROM public.notifications
  WHERE related_entity_id = v_admission.id
    AND category = 'payment'
    AND recipient_role = 'accountant'
    AND metadata->>'workflow' = 'discharge_billing_handoff'
  ORDER BY created_at DESC
  LIMIT 1;

  IF v_notification_id IS NULL THEN
    INSERT INTO public.notifications(
      recipient_role, title, message, severity, category, link,
      related_patient_id, related_entity_id, metadata
    )
    VALUES (
      'accountant',
      'Discharged patient ready for billing reconciliation',
      pg_catalog.format(
        '%s (%s) has been discharged. Reconcile the complete patient bill, including inpatient services, before settlement.',
        COALESCE(v_patient_name, 'Patient'),
        COALESCE(v_patient_code, 'no patient code')
      ),
      'warning',
      'payment',
      '/billing',
      v_admission.patient_id,
      v_admission.id,
      pg_catalog.jsonb_build_object(
        'workflow', 'discharge_billing_handoff',
        'admission_id', v_admission.id,
        'discharged_at', v_discharged_at
      )
    )
    RETURNING id INTO v_notification_id;
  END IF;

  PERFORM public.record_system_audit(
    'patient_discharged',
    'admissions',
    'admission',
    v_admission.id,
    'info',
    pg_catalog.jsonb_build_object(
      'patient_id', v_admission.patient_id,
      'bed_id', v_bed.id,
      'bed_status', CASE WHEN v_bed.id IS NULL THEN NULL ELSE 'cleaning' END,
      'billing_handoff_notification_id', v_notification_id
    )
  );

  RETURN pg_catalog.jsonb_build_object(
    'admission_id', v_admission.id,
    'patient_id', v_admission.patient_id,
    'status', 'discharged',
    'bed_id', v_bed.id,
    'bed_status', CASE WHEN v_bed.id IS NULL THEN NULL ELSE 'cleaning' END,
    'billing_handoff', 'pending',
    'notification_id', v_notification_id
  );
END;
$$;

REVOKE ALL ON FUNCTION public.discharge_admission_workflow(UUID,TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.discharge_admission_workflow(UUID,TEXT) TO authenticated;


-- Existing-bed creation is intentionally separate from movement, but its RPC must
-- remain the only client-authorized creation boundary. Prevent authenticated
-- callers from directly inserting/deleting bed rows.
REVOKE INSERT, UPDATE, DELETE ON public.ward_beds FROM authenticated;

-- Cleaning/available/maintenance transitions are administrative inventory state,
-- not patient movement. Keep them server-authoritative and reject transitions
-- that would leave patient/admission ownership behind.
CREATE OR REPLACE FUNCTION public.set_ward_bed_status(
  _bed_id UUID,
  _status TEXT,
  _notes TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $$
DECLARE
  uid UUID := auth.uid();
  v_bed public.ward_beds%ROWTYPE;
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF NOT (
    public.has_role(uid,'admin')
    OR public.has_role(uid,'nurse')
    OR public.has_role(uid,'specialist_nurse')
  ) THEN
    RAISE EXCEPTION 'Nursing role required';
  END IF;

  IF _status NOT IN ('available','cleaning','maintenance','blocked','reserved') THEN
    RAISE EXCEPTION 'Unsupported bed status';
  END IF;

  SELECT *
    INTO v_bed
  FROM public.ward_beds
  WHERE id = _bed_id
  FOR UPDATE;

  IF v_bed.id IS NULL THEN
    RAISE EXCEPTION 'Bed not found';
  END IF;

  IF v_bed.status = 'occupied' OR v_bed.patient_id IS NOT NULL OR v_bed.admission_id IS NOT NULL THEN
    RAISE EXCEPTION 'Occupied or patient-linked beds must use the inpatient movement or discharge workflow';
  END IF;

  UPDATE public.ward_beds
  SET status = _status,
      notes = COALESCE(NULLIF(pg_catalog.btrim(_notes), ''), notes),
      updated_at = now(),
      released_at = CASE WHEN _status = 'available' THEN COALESCE(released_at, now()) ELSE released_at END
  WHERE id = v_bed.id;

  RETURN pg_catalog.jsonb_build_object(
    'bed_id', v_bed.id,
    'status', _status
  );
END;
$$;

REVOKE ALL ON FUNCTION public.set_ward_bed_status(UUID,TEXT,TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_ward_bed_status(UUID,TEXT,TEXT) TO authenticated;


-- Harden bed creation and lifecycle transitions. Creation is a server boundary
-- and must not create duplicate bed identities within a ward.
CREATE OR REPLACE FUNCTION public.create_ward_bed(
  _ward_id UUID,
  _bed_number TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $$
DECLARE
  uid UUID := auth.uid();
  v_id UUID;
  v_bed_number TEXT := NULLIF(pg_catalog.btrim(_bed_number), '');
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF NOT (
    public.has_role(uid,'admin')
    OR public.has_role(uid,'nurse')
    OR public.has_role(uid,'specialist_nurse')
  ) THEN
    RAISE EXCEPTION 'Nursing role required';
  END IF;

  IF _ward_id IS NULL OR v_bed_number IS NULL THEN
    RAISE EXCEPTION 'Ward and bed number are required';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.ward_units WHERE id = _ward_id AND active = true
  ) THEN
    RAISE EXCEPTION 'Active ward not found';
  END IF;

  -- Serialize creation within a ward so two concurrent requests cannot both
  -- pass the duplicate check before either insert commits.
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(_ward_id::text, 0)
  );

  IF EXISTS (
    SELECT 1
    FROM public.ward_beds
    WHERE ward_id = _ward_id
      AND lower(pg_catalog.btrim(bed_number)) = lower(v_bed_number)
  ) THEN
    RAISE EXCEPTION 'Bed number already exists in this ward';
  END IF;

  INSERT INTO public.ward_beds(ward_id, bed_number, status)
  VALUES (_ward_id, v_bed_number, 'available')
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.create_ward_bed(UUID,TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_ward_bed(UUID,TEXT) TO authenticated;

-- A bed may only become available after a non-occupied lifecycle state.
-- Patient ownership always remains under the movement/discharge workflows.
CREATE OR REPLACE FUNCTION public.set_ward_bed_status(
  _bed_id UUID,
  _status TEXT,
  _notes TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $$
DECLARE
  uid UUID := auth.uid();
  v_bed public.ward_beds%ROWTYPE;
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF NOT (
    public.has_role(uid,'admin')
    OR public.has_role(uid,'nurse')
    OR public.has_role(uid,'specialist_nurse')
  ) THEN
    RAISE EXCEPTION 'Nursing role required';
  END IF;

  IF _status NOT IN ('available','cleaning','maintenance','blocked','reserved') THEN
    RAISE EXCEPTION 'Unsupported bed status';
  END IF;

  SELECT *
    INTO v_bed
  FROM public.ward_beds
  WHERE id = _bed_id
  FOR UPDATE;

  IF v_bed.id IS NULL THEN
    RAISE EXCEPTION 'Bed not found';
  END IF;

  IF v_bed.status = 'occupied'
     OR v_bed.patient_id IS NOT NULL
     OR v_bed.admission_id IS NOT NULL THEN
    RAISE EXCEPTION 'Occupied or patient-linked beds must use the inpatient movement or discharge workflow';
  END IF;

  IF _status = 'available'
     AND v_bed.status NOT IN ('cleaning','maintenance','blocked','reserved','available') THEN
    RAISE EXCEPTION 'Bed cannot transition to available from its current state';
  END IF;

  UPDATE public.ward_beds
  SET status = _status,
      notes = COALESCE(NULLIF(pg_catalog.btrim(_notes), ''), notes),
      updated_at = now(),
      released_at = CASE
        WHEN _status = 'available' THEN COALESCE(released_at, now())
        ELSE released_at
      END
  WHERE id = v_bed.id;

  RETURN pg_catalog.jsonb_build_object(
    'bed_id', v_bed.id,
    'previous_status', v_bed.status,
    'status', _status
  );
END;
$$;

REVOKE ALL ON FUNCTION public.set_ward_bed_status(UUID,TEXT,TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_ward_bed_status(UUID,TEXT,TEXT) TO authenticated;


-- Reconcile legacy admission creation with the canonical inpatient bed workflow.
-- A supplied bed is treated as a ward_beds UUID; otherwise the admission remains
-- admitted/awaiting-bed until placement occurs through the movement workflow.
CREATE OR REPLACE FUNCTION public.create_admission_workflow(
  _patient_id UUID,
  _ward TEXT,
  _bed TEXT DEFAULT NULL,
  _reason TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $$
DECLARE
  uid UUID := auth.uid();
  v_admission UUID;
  v_bed_id UUID;
  v_ward_name TEXT;
  v_bed_ward UUID;
  v_transfer JSONB;
  v_ward_input TEXT := NULLIF(pg_catalog.btrim(_ward), '');
  v_bed_input TEXT := NULLIF(pg_catalog.btrim(_bed), '');
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF NOT (
    public.has_role(uid,'admin')
    OR public.has_role(uid,'practitioner')
    OR public.has_role(uid,'nurse')
    OR public.has_role(uid,'midwife')
  ) THEN
    RAISE EXCEPTION 'Admission creation is not permitted';
  END IF;

  IF _patient_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.patients WHERE id = _patient_id
  ) THEN
    RAISE EXCEPTION 'Patient not found';
  END IF;

  IF v_ward_input IS NULL THEN
    RAISE EXCEPTION 'Ward is required';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(_patient_id::text, 0)
  );

  IF EXISTS (
    SELECT 1
    FROM public.admissions
    WHERE patient_id = _patient_id
      AND status = 'admitted'
  ) THEN
    RAISE EXCEPTION 'Patient already has an active admission';
  END IF;

  SELECT wu.id, wu.name
    INTO v_bed_ward, v_ward_name
  FROM public.ward_units wu
  WHERE wu.active = true
    AND (
      lower(pg_catalog.btrim(wu.name)) = lower(v_ward_input)
      OR lower(pg_catalog.btrim(wu.code)) = lower(v_ward_input)
    )
  ORDER BY wu.name
  LIMIT 1;

  IF v_bed_ward IS NULL THEN
    RAISE EXCEPTION 'Active ward not found';
  END IF;

  IF v_bed_input IS NOT NULL THEN
    IF v_bed_input !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' THEN
      RAISE EXCEPTION 'Bed must be a valid ward bed ID';
    END IF;

    v_bed_id := v_bed_input::uuid;

    SELECT wb.ward_id
      INTO v_bed_ward
    FROM public.ward_beds wb
    WHERE wb.id = v_bed_id
    FOR SHARE;

    IF v_bed_ward IS NULL THEN
      RAISE EXCEPTION 'Bed not found';
    END IF;

    IF NOT EXISTS (
      SELECT 1
      FROM public.ward_units wu
      WHERE wu.id = v_bed_ward
        AND wu.active = true
        AND lower(pg_catalog.btrim(wu.name)) = lower(v_ward_input)
    ) AND NOT EXISTS (
      SELECT 1
      FROM public.ward_units wu
      WHERE wu.id = v_bed_ward
        AND wu.active = true
        AND lower(pg_catalog.btrim(wu.code)) = lower(v_ward_input)
    ) THEN
      RAISE EXCEPTION 'Bed does not belong to the selected ward';
    END IF;
  END IF;

  INSERT INTO public.admissions(
    patient_id,
    ward,
    bed,
    reason,
    admitted_by,
    status,
    admitted_at
  )
  VALUES (
    _patient_id,
    v_ward_name,
    NULL,
    NULLIF(pg_catalog.btrim(_reason), ''),
    uid,
    'admitted',
    now()
  )
  RETURNING id INTO v_admission;

  IF v_bed_id IS NOT NULL THEN
    v_transfer := public.transfer_patient_ward_bed_workflow(
      _patient_id,
      v_admission,
      v_bed_id,
      NULL,
      NULL,
      NULL
    );

    RETURN jsonb_build_object(
      'admission_id', v_admission,
      'status', 'admitted',
      'bed_placement', v_transfer
    );
  END IF;

  RETURN jsonb_build_object(
    'admission_id', v_admission,
    'status', 'admitted',
    'bed_placement', NULL,
    'awaiting_bed', TRUE
  );
END;
$$;

REVOKE ALL ON FUNCTION public.create_admission_workflow(UUID,TEXT,TEXT,TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_admission_workflow(UUID,TEXT,TEXT,TEXT) TO authenticated;

-- The Patient Hub convenience entrypoint must not create an admission through
-- a second mutation path. Delegate to the canonical admission workflow.
CREATE OR REPLACE FUNCTION public.create_patient_admission(
  _patient_id UUID,
  _reason TEXT,
  _ward TEXT DEFAULT NULL,
  _bed TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $$
BEGIN
  RETURN public.create_admission_workflow(
    _patient_id,
    _ward,
    _bed,
    _reason
  );
END;
$$;

DROP FUNCTION IF EXISTS public.create_patient_admission(UUID,TEXT,TEXT,UUID);

REVOKE ALL ON FUNCTION public.create_patient_admission(UUID,TEXT,TEXT,TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_patient_admission(UUID,TEXT,TEXT,TEXT) TO authenticated;

-- Harden encounter admission against duplicate active admissions and stale wards.
CREATE OR REPLACE FUNCTION public.admit_encounter_workflow(
  _encounter_id UUID,
  _reason TEXT DEFAULT NULL,
  _ward TEXT DEFAULT NULL,
  _emergency_override BOOLEAN DEFAULT TRUE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $$
DECLARE
  v_enc public.encounters%ROWTYPE;
  v_admission UUID;
  v_override BOOLEAN := FALSE;
  v_order RECORD;
  v_ward_name TEXT;
  uid UUID := auth.uid();
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF NOT (
    public.has_role(uid,'admin')
    OR public.has_role(uid,'practitioner')
    OR public.has_role(uid,'nurse')
    OR public.has_role(uid,'midwife')
    OR public.has_role(uid,'specialist_nurse')
  ) THEN
    RAISE EXCEPTION 'Admission is not permitted for this role';
  END IF;

  SELECT *
    INTO v_enc
  FROM public.encounters
  WHERE id = _encounter_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Encounter not found';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.patients WHERE id = v_enc.patient_id
  ) THEN
    RAISE EXCEPTION 'Encounter patient not found';
  END IF;

  IF v_enc.status = 'cancelled' THEN
    RAISE EXCEPTION 'Cancelled encounters cannot be admitted';
  END IF;

  IF v_enc.admission_id IS NOT NULL THEN
    RETURN jsonb_build_object(
      'admission_id', v_enc.admission_id,
      'override', FALSE,
      'existing', TRUE
    );
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_enc.patient_id::text, 0)
  );

  IF EXISTS (
    SELECT 1
    FROM public.admissions
    WHERE patient_id = v_enc.patient_id
      AND status = 'admitted'
  ) THEN
    RAISE EXCEPTION 'Patient already has an active admission';
  END IF;

  IF NULLIF(pg_catalog.btrim(_ward), '') IS NOT NULL THEN
    SELECT wu.name
      INTO v_ward_name
    FROM public.ward_units wu
    WHERE wu.active = true
      AND (
        lower(pg_catalog.btrim(wu.name)) = lower(pg_catalog.btrim(_ward))
        OR lower(pg_catalog.btrim(wu.code)) = lower(pg_catalog.btrim(_ward))
      )
    ORDER BY wu.name
    LIMIT 1;

    IF v_ward_name IS NULL THEN
      RAISE EXCEPTION 'Active ward not found';
    END IF;
  END IF;

  SELECT COALESCE(
    allow_treatment_before_deposit,
    FALSE
  )
  AND COALESCE(admission_financial_override_enabled,FALSE)
  AND COALESCE(allow_clinical_emergency_override,FALSE)
  INTO v_override
  FROM public.facility_configuration
  WHERE id = 'default'
  LIMIT 1;

  v_override := COALESCE(v_override,FALSE)
    AND COALESCE(_emergency_override,TRUE);

  INSERT INTO public.admissions(
    patient_id, encounter_id, ward, reason, admitted_by, status
  )
  VALUES(
    v_enc.patient_id,
    v_enc.id,
    v_ward_name,
    COALESCE(NULLIF(pg_catalog.btrim(_reason),''),'Clinical admission'),
    uid,
    'admitted'
  )
  RETURNING id INTO v_admission;

  UPDATE public.encounters
  SET admission_id = v_admission,
      updated_at = now()
  WHERE id = v_enc.id;

  IF v_override THEN
    FOR v_order IN
      SELECT *
      FROM public.service_orders
      WHERE encounter_id = v_enc.id
        AND status = 'pending_payment_approval'
      FOR UPDATE
    LOOP
      INSERT INTO public.billing_overrides(
        service_order_id,patient_id,department,related_entity_id,
        reason,overridden_by,approved_by,approved_at
      )
      VALUES(
        v_order.id,v_order.patient_id,v_order.department,v_order.related_entity_id,
        COALESCE(NULLIF(pg_catalog.btrim(_reason),''),
                 'Emergency treatment before deposit'),
        uid,uid,now()
      )
      ON CONFLICT(service_order_id) DO UPDATE SET
        reason=EXCLUDED.reason,
        overridden_by=EXCLUDED.overridden_by,
        approved_by=EXCLUDED.approved_by,
        approved_at=EXCLUDED.approved_at;

      UPDATE public.service_orders
      SET status='released',
          approved_at=now(),
          approved_by=uid,
          released_at=now(),
          released_by=uid,
          release_reason='Emergency admission financial override',
          notes=concat_ws(E'\n',notes,
            'Emergency admission financial override: treatment released before deposit.'),
          updated_at=now()
      WHERE id=v_order.id;

      INSERT INTO public.department_queues(
        service_order_id,patient_id,department,related_encounter_id,
        related_invoice_id,payment_required,payment_satisfied,priority,
        reason,created_by,queued_at,status
      )
      VALUES(
        v_order.id,v_order.patient_id,v_order.department,v_order.encounter_id,
        v_order.invoice_id,v_order.payment_required,TRUE,'normal',
        v_order.service_name,uid,now(),'queued'
      )
      ON CONFLICT(service_order_id) DO UPDATE SET
        payment_satisfied=TRUE,
        status=CASE
          WHEN public.department_queues.status='cancelled' THEN 'queued'
          ELSE public.department_queues.status
        END,
        updated_at=now();
    END LOOP;

    PERFORM public.record_system_audit(
      'admission_financial_override',
      'admissions',
      'admission',
      v_admission,
      'critical',
      jsonb_build_object(
        'encounter_id',v_enc.id,
        'patient_id',v_enc.patient_id,
        'override',TRUE
      )
    );
  END IF;

  PERFORM public.record_system_audit(
    'patient_admitted',
    'admissions',
    'admission',
    v_admission,
    'info',
    jsonb_build_object(
      'encounter_id',v_enc.id,
      'patient_id',v_enc.patient_id,
      'financial_override',v_override
    )
  );

  RETURN jsonb_build_object(
    'admission_id',v_admission,
    'override',v_override,
    'status','admitted'
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admit_encounter_workflow(UUID,TEXT,TEXT,BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admit_encounter_workflow(UUID,TEXT,TEXT,BOOLEAN) TO authenticated;
