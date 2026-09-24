-- Atomic inpatient bed transfer boundary.
-- Branch-only migration; production is intentionally unchanged.

CREATE OR REPLACE FUNCTION public.transfer_inpatient_bed(
  _admission_id uuid,
  _target_bed_id uuid,
  _summary text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog, public'
AS $function$
DECLARE
  v_admission public.admissions%ROWTYPE;
  v_target public.ward_beds%ROWTYPE;
  v_source public.ward_beds%ROWTYPE;
  v_target_ward public.ward_units%ROWTYPE;
  v_transition_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF NOT (
    public.has_role(auth.uid(), 'admin') OR
    public.has_role(auth.uid(), 'nurse') OR
    public.has_role(auth.uid(), 'specialist_nurse') OR
    public.has_role(auth.uid(), 'practitioner') OR
    public.has_role(auth.uid(), 'midwife')
  ) THEN
    RAISE EXCEPTION 'Inpatient transfer is not permitted';
  END IF;

  IF _admission_id IS NULL OR _target_bed_id IS NULL THEN
    RAISE EXCEPTION 'Admission and target bed are required';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(_admission_id::text, 0));

  SELECT * INTO v_admission
  FROM public.admissions
  WHERE id = _admission_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Admission not found';
  END IF;

  IF v_admission.status <> 'admitted' THEN
    RAISE EXCEPTION 'Only active admissions can be transferred';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.patients WHERE id = v_admission.patient_id) THEN
    RAISE EXCEPTION 'Admission patient not found';
  END IF;

  SELECT * INTO v_target
  FROM public.ward_beds
  WHERE id = _target_bed_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Target bed not found';
  END IF;

  IF v_target.status <> 'available'
     OR v_target.patient_id IS NOT NULL
     OR v_target.admission_id IS NOT NULL THEN
    RAISE EXCEPTION 'Target bed is not available';
  END IF;

  SELECT * INTO v_source
  FROM public.ward_beds
  WHERE admission_id = v_admission.id
    AND patient_id = v_admission.patient_id
    AND status = 'occupied'
  ORDER BY occupied_at DESC NULLS LAST
  LIMIT 1
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Active admission has no occupied source bed';
  END IF;

  IF v_source.id = v_target.id THEN
    RAISE EXCEPTION 'Target bed is already the current bed';
  END IF;

  SELECT * INTO v_target_ward
  FROM public.ward_units
  WHERE id = v_target.ward_id
    AND active = true
  FOR SHARE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Target ward is not active';
  END IF;

  UPDATE public.ward_beds
  SET patient_id = NULL,
      admission_id = NULL,
      status = 'cleaning',
      released_at = now(),
      updated_at = now()
  WHERE id = v_source.id;

  UPDATE public.ward_beds
  SET patient_id = v_admission.patient_id,
      admission_id = v_admission.id,
      status = 'occupied',
      occupied_at = now(),
      released_at = NULL,
      updated_at = now()
  WHERE id = v_target.id;

  UPDATE public.admissions
  SET ward = v_target_ward.name,
      bed = v_target.bed_number,
      updated_at = now()
  WHERE id = v_admission.id;

  INSERT INTO public.care_transitions(
    patient_id,
    admission_id,
    transition_type,
    status,
    destination,
    summary,
    medications_reconciled,
    follow_up_required,
    responsible_officer,
    completed_at
  )
  VALUES(
    v_admission.patient_id,
    v_admission.id,
    'transfer',
    'completed',
    v_target_ward.name || ' / ' || v_target.bed_number,
    NULLIF(btrim(_summary), ''),
    false,
    false,
    auth.uid(),
    now()
  )
  RETURNING id INTO v_transition_id;

  PERFORM public.record_system_audit(
    'inpatient_bed_transferred',
    'ward_beds',
    'ward_bed',
    v_target.id,
    'info',
    jsonb_build_object(
      'patient_id', v_admission.patient_id,
      'admission_id', v_admission.id,
      'source_bed_id', v_source.id,
      'target_bed_id', v_target.id,
      'target_ward_id', v_target.ward_id,
      'care_transition_id', v_transition_id
    )
  );

  RETURN jsonb_build_object(
    'admission_id', v_admission.id,
    'source_bed_id', v_source.id,
    'target_bed_id', v_target.id,
    'care_transition_id', v_transition_id,
    'status', 'completed'
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.transfer_inpatient_bed(uuid, uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.transfer_inpatient_bed(uuid, uuid, text) TO authenticated;
