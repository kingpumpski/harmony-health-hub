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
