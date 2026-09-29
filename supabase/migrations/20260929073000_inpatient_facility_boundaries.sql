-- Enforce facility isolation across inpatient admission and bed movement workflows.
CREATE OR REPLACE FUNCTION public.transfer_patient_ward_bed_workflow(
  _patient_id uuid,
  _admission_id uuid,
  _destination_bed_id uuid,
  _source_bed_id uuid DEFAULT NULL::uuid,
  _reason text DEFAULT NULL::text,
  _notes text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
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
  v_source_facility UUID;
  v_destination_facility UUID;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;

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

  SELECT * INTO v_admission
  FROM public.admissions
  WHERE id = _admission_id AND patient_id = _patient_id
  FOR UPDATE;

  IF v_admission.id IS NULL THEN RAISE EXCEPTION 'Active admission not found for patient'; END IF;
  IF v_admission.status <> 'admitted' THEN RAISE EXCEPTION 'Admission is not active'; END IF;

  SELECT * INTO v_destination
  FROM public.ward_beds
  WHERE id = _destination_bed_id
  FOR UPDATE;

  IF v_destination.id IS NULL THEN RAISE EXCEPTION 'Destination bed not found'; END IF;
  IF v_destination.status <> 'available' OR v_destination.patient_id IS NOT NULL THEN
    RAISE EXCEPTION 'Destination bed is not available';
  END IF;

  v_destination_facility := v_destination.facility_id;
  IF NOT public.has_facility_access(uid, v_destination_facility) THEN
    RAISE EXCEPTION 'Facility access required for destination bed';
  END IF;

  IF _source_bed_id IS NOT NULL AND _source_bed_id = _destination_bed_id THEN
    RAISE EXCEPTION 'Source and destination beds must differ';
  END IF;

  SELECT count(*) INTO v_source_count
  FROM public.ward_beds
  WHERE patient_id = _patient_id AND status = 'occupied';

  IF _source_bed_id IS NULL THEN
    IF v_source_count > 1 THEN RAISE EXCEPTION 'Patient has multiple occupied ward beds'; END IF;
    IF v_source_count = 1 THEN
      SELECT * INTO v_source
      FROM public.ward_beds
      WHERE patient_id = _patient_id AND status = 'occupied' AND admission_id = _admission_id
      FOR UPDATE;
      IF v_source.id IS NULL THEN RAISE EXCEPTION 'Current occupied bed does not match the admission'; END IF;
    END IF;
  ELSE
    SELECT * INTO v_source
    FROM public.ward_beds
    WHERE id = _source_bed_id
    FOR UPDATE;
    IF v_source.id IS NULL THEN RAISE EXCEPTION 'Source bed not found'; END IF;
    IF v_source.patient_id IS DISTINCT FROM _patient_id
       OR v_source.admission_id IS DISTINCT FROM _admission_id
       OR v_source.status <> 'occupied' THEN
      RAISE EXCEPTION 'Source bed is not occupied by this admitted patient';
    END IF;
  END IF;

  IF v_source.id IS NOT NULL THEN
    v_source_facility := v_source.facility_id;
    IF NOT public.has_facility_access(uid, v_source_facility) THEN
      RAISE EXCEPTION 'Facility access required for source bed';
    END IF;
    IF v_source_facility IS DISTINCT FROM v_destination_facility THEN
      RAISE EXCEPTION 'Cross-facility inpatient transfer is not permitted';
    END IF;

    UPDATE public.ward_beds
    SET patient_id = NULL, admission_id = NULL, status = 'available',
        released_at = now(), updated_at = now()
    WHERE id = v_source.id;
    v_movement_type := 'transfer';
  ELSE
    v_movement_type := 'placement';
  END IF;

  UPDATE public.ward_beds
  SET patient_id = _patient_id, admission_id = _admission_id, status = 'occupied',
      occupied_at = now(), released_at = NULL, updated_at = now()
  WHERE id = v_destination.id;

  SELECT wu.name || ' / ' || v_destination.bed_number INTO v_destination_label
  FROM public.ward_units wu WHERE wu.id = v_destination.ward_id;
  IF v_destination_label IS NULL THEN v_destination_label := v_destination.bed_number; END IF;

  UPDATE public.admissions
  SET ward = (SELECT wu.name FROM public.ward_units wu WHERE wu.id = v_destination.ward_id),
      bed = v_destination.bed_number, updated_at = now()
  WHERE id = v_admission.id;

  INSERT INTO public.inpatient_bed_movements (
    patient_id, admission_id, movement_type, source_bed_id, destination_bed_id,
    reason, notes, moved_by
  ) VALUES (
    _patient_id, _admission_id, v_movement_type, v_source.id, v_destination.id,
    NULLIF(pg_catalog.btrim(_reason), ''), NULLIF(pg_catalog.btrim(_notes), ''), uid
  ) RETURNING id INTO v_movement_id;

  INSERT INTO public.care_transitions (
    patient_id, admission_id, transition_type, status, destination, summary,
    responsible_officer, completed_at
  ) VALUES (
    _patient_id, _admission_id, 'transfer', 'completed', v_destination_label,
    COALESCE(NULLIF(pg_catalog.btrim(_reason), ''),
      CASE WHEN v_movement_type = 'placement'
        THEN 'Patient placed in an inpatient bed.'
        ELSE 'Patient transferred to a new inpatient bed.' END),
    uid, now()
  ) RETURNING id INTO v_transition_id;

  PERFORM public.record_system_audit(
    CASE WHEN v_movement_type = 'placement'
      THEN 'inpatient_bed_placed' ELSE 'inpatient_bed_transferred' END,
    'inpatient', 'inpatient_bed_movement', v_movement_id, 'info',
    pg_catalog.jsonb_build_object(
      'patient_id', _patient_id, 'admission_id', _admission_id,
      'source_bed_id', v_source.id, 'destination_bed_id', v_destination.id,
      'destination', v_destination_label, 'transition_id', v_transition_id
    )
  );

  RETURN pg_catalog.jsonb_build_object(
    'movement_id', v_movement_id, 'transition_id', v_transition_id,
    'movement_type', v_movement_type, 'source_bed_id', v_source.id,
    'destination_bed_id', v_destination.id, 'destination', v_destination_label,
    'status', 'completed'
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.create_admission_workflow(
  _patient_id uuid,
  _ward text,
  _bed text DEFAULT NULL::text,
  _reason text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  uid UUID := auth.uid();
  v_admission UUID;
  v_bed_id UUID;
  v_ward_name TEXT;
  v_bed_ward UUID;
  v_ward_facility UUID;
  v_transfer JSONB;
  v_ward_input TEXT := NULLIF(pg_catalog.btrim(_ward), '');
  v_bed_input TEXT := NULLIF(pg_catalog.btrim(_bed), '');
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;

  IF NOT (
    public.has_role(uid,'admin') OR public.has_role(uid,'practitioner')
    OR public.has_role(uid,'nurse') OR public.has_role(uid,'midwife')
  ) THEN RAISE EXCEPTION 'Admission creation is not permitted'; END IF;

  IF _patient_id IS NULL OR NOT EXISTS (SELECT 1 FROM public.patients WHERE id = _patient_id) THEN
    RAISE EXCEPTION 'Patient not found';
  END IF;
  IF v_ward_input IS NULL THEN RAISE EXCEPTION 'Ward is required'; END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(_patient_id::text, 0));

  IF EXISTS (SELECT 1 FROM public.admissions WHERE patient_id = _patient_id AND status = 'admitted') THEN
    RAISE EXCEPTION 'Patient already has an active admission';
  END IF;

  SELECT wu.id, wu.name, wu.facility_id
  INTO v_bed_ward, v_ward_name, v_ward_facility
  FROM public.ward_units wu
  WHERE wu.active = true
    AND (lower(pg_catalog.btrim(wu.name)) = lower(v_ward_input)
      OR lower(pg_catalog.btrim(wu.code)) = lower(v_ward_input))
  ORDER BY wu.name
  LIMIT 1;

  IF v_bed_ward IS NULL THEN RAISE EXCEPTION 'Active ward not found'; END IF;
  IF NOT public.has_facility_access(uid, v_ward_facility) THEN
    RAISE EXCEPTION 'Facility access required for admission ward';
  END IF;

  IF v_bed_input IS NOT NULL THEN
    IF v_bed_input !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' THEN
      RAISE EXCEPTION 'Bed must be a valid ward bed ID';
    END IF;
    v_bed_id := v_bed_input::uuid;

    SELECT wb.ward_id INTO v_bed_ward
    FROM public.ward_beds wb WHERE wb.id = v_bed_id FOR SHARE;

    IF v_bed_ward IS NULL THEN RAISE EXCEPTION 'Bed not found'; END IF;

    IF NOT EXISTS (
      SELECT 1 FROM public.ward_units wu
      WHERE wu.id = v_bed_ward AND wu.active = true
        AND (lower(pg_catalog.btrim(wu.name)) = lower(v_ward_input)
          OR lower(pg_catalog.btrim(wu.code)) = lower(v_ward_input))
        AND wu.facility_id = v_ward_facility
    ) THEN
      RAISE EXCEPTION 'Bed does not belong to the selected ward';
    END IF;

    IF NOT EXISTS (
      SELECT 1 FROM public.ward_beds wb
      WHERE wb.id = v_bed_id AND wb.facility_id = v_ward_facility
    ) THEN
      RAISE EXCEPTION 'Bed does not belong to the admission facility';
    END IF;
  END IF;

  INSERT INTO public.admissions(
    patient_id, ward, bed, reason, admitted_by, status, admitted_at
  ) VALUES (
    _patient_id, v_ward_name, NULL, NULLIF(pg_catalog.btrim(_reason), ''), uid,
    'admitted', now()
  ) RETURNING id INTO v_admission;

  IF v_bed_id IS NOT NULL THEN
    v_transfer := public.transfer_patient_ward_bed_workflow(
      _patient_id, v_admission, v_bed_id, NULL, NULL, NULL
    );
    RETURN pg_catalog.jsonb_build_object(
      'admission_id', v_admission, 'status', 'admitted',
      'bed_placement', v_transfer
    );
  END IF;

  RETURN pg_catalog.jsonb_build_object(
    'admission_id', v_admission, 'status', 'admitted',
    'bed_placement', NULL, 'awaiting_bed', TRUE
  );
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.transfer_patient_ward_bed_workflow(uuid,uuid,uuid,uuid,text,text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.transfer_patient_ward_bed_workflow(uuid,uuid,uuid,uuid,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.transfer_patient_ward_bed_workflow(uuid,uuid,uuid,uuid,text,text) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.create_admission_workflow(uuid,text,text,text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.create_admission_workflow(uuid,text,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_admission_workflow(uuid,text,text,text) TO authenticated;