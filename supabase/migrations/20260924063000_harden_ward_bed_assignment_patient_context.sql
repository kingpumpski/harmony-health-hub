-- Harden ward-bed assignment against cross-patient and orphaned references.
CREATE OR REPLACE FUNCTION public.assign_ward_bed(
  _bed_id uuid,
  _patient_id uuid,
  _admission_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  b public.ward_beds%ROWTYPE;
  uid uuid := auth.uid();
  admission_patient_id uuid;
  admission_status text;
BEGIN
  IF uid IS NULL OR NOT (
    public.has_role(uid,'admin')
    OR public.has_role(uid,'nurse')
    OR public.has_role(uid,'specialist_nurse')
  ) THEN
    RAISE EXCEPTION 'Nursing role required';
  END IF;

  IF _patient_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.patients WHERE id = _patient_id
  ) THEN
    RAISE EXCEPTION 'Patient not found';
  END IF;

  SELECT * INTO b
  FROM public.ward_beds
  WHERE id = _bed_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Bed not found';
  END IF;

  IF b.status <> 'available' OR b.patient_id IS NOT NULL THEN
    RAISE EXCEPTION 'Bed is not available';
  END IF;

  IF _admission_id IS NOT NULL THEN
    SELECT a.patient_id, a.status
      INTO admission_patient_id, admission_status
    FROM public.admissions a
    WHERE a.id = _admission_id
    FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Admission not found';
    END IF;

    IF admission_patient_id IS DISTINCT FROM _patient_id THEN
      RAISE EXCEPTION 'Admission does not belong to patient';
    END IF;

    IF admission_status IS DISTINCT FROM 'admitted' THEN
      RAISE EXCEPTION 'Admission is not active';
    END IF;
  END IF;

  UPDATE public.ward_beds
  SET patient_id = _patient_id,
      admission_id = _admission_id,
      status = 'occupied',
      occupied_at = now(),
      released_at = NULL,
      updated_at = now()
  WHERE id = _bed_id;

  RETURN jsonb_build_object(
    'bed_id', _bed_id,
    'status', 'occupied',
    'patient_id', _patient_id,
    'admission_id', _admission_id
  );
END;
$$;

REVOKE ALL ON FUNCTION public.assign_ward_bed(uuid, uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.assign_ward_bed(uuid, uuid, uuid) TO authenticated;
