BEGIN;

CREATE OR REPLACE FUNCTION public.release_ward_bed(
  _bed_id uuid,
  _notes text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  uid uuid := auth.uid();
  v_patient_id uuid;
  v_admission_id uuid;
  v_admission_patient_id uuid;
  v_admission_status text;
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF NOT (
    public.has_role(uid, 'admin')
    OR public.has_role(uid, 'nurse')
    OR public.has_role(uid, 'specialist_nurse')
  ) THEN
    RAISE EXCEPTION 'Nursing role required';
  END IF;

  SELECT patient_id, admission_id
    INTO v_patient_id, v_admission_id
  FROM public.ward_beds
  WHERE id = _bed_id
    AND status = 'occupied'
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Occupied bed not found';
  END IF;

  IF v_patient_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.patients WHERE id = v_patient_id
  ) THEN
    RAISE EXCEPTION 'Bed patient not found';
  END IF;

  IF v_admission_id IS NOT NULL THEN
    SELECT patient_id, status
      INTO v_admission_patient_id, v_admission_status
    FROM public.admissions
    WHERE id = v_admission_id
    FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Linked admission not found';
    END IF;

    IF v_patient_id IS NULL OR v_admission_patient_id IS NULL
       OR v_admission_patient_id <> v_patient_id THEN
      RAISE EXCEPTION 'Bed admission patient context mismatch';
    END IF;

    IF v_admission_status = 'admitted' THEN
      RAISE EXCEPTION 'Discharge or transfer the active admission before releasing this bed';
    END IF;
  END IF;

  UPDATE public.ward_beds
  SET patient_id = NULL,
      admission_id = NULL,
      status = 'cleaning',
      released_at = now(),
      notes = COALESCE(NULLIF(btrim(_notes), ''), notes),
      updated_at = now()
  WHERE id = _bed_id
    AND status = 'occupied';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Occupied bed changed before release';
  END IF;

  RETURN jsonb_build_object(
    'bed_id', _bed_id,
    'status', 'cleaning'
  );
END;
$$;

REVOKE ALL ON FUNCTION public.release_ward_bed(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.release_ward_bed(uuid, text) TO authenticated;

COMMIT;
