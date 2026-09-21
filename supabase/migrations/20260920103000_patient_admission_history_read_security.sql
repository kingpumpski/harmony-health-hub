-- Patient-scoped admission history read boundary for the Patient Hub.
CREATE OR REPLACE FUNCTION public.get_patient_admission_history(_patient_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role text;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  SELECT role::text INTO v_role
  FROM public.profiles
  WHERE id = auth.uid();

  IF v_role IS NULL THEN
    RAISE EXCEPTION 'Staff profile required';
  END IF;

  IF v_role NOT IN (
    'admin','practitioner','nurse','midwife','specialist_nurse'
  ) THEN
    RAISE EXCEPTION 'Admission history access is not permitted';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.patients p
    WHERE p.id = _patient_id
      AND p.status <> 'inactive'
  ) THEN
    RAISE EXCEPTION 'Patient not found or inactive';
  END IF;

  RETURN COALESCE((
    SELECT jsonb_agg(to_jsonb(x) ORDER BY x.admitted_at DESC)
    FROM (
      SELECT
        a.id,
        a.patient_id,
        a.admitted_at,
        a.discharged_at,
        a.ward,
        a.bed,
        a.reason,
        a.status,
        a.discharge_summary
      FROM public.admissions a
      WHERE a.patient_id = _patient_id
      ORDER BY a.admitted_at DESC
      LIMIT 50
    ) x
  ), '[]'::jsonb);
END;
$$;

REVOKE ALL ON FUNCTION public.get_patient_admission_history(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_patient_admission_history(uuid) TO authenticated;
