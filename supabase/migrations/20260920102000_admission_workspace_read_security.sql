-- Secure inpatient read workspace for staff-facing admission management.
-- Keep admissions table RLS intact; staff reads go through this least-privilege RPC.

CREATE OR REPLACE FUNCTION public.get_admission_workspace(_limit integer DEFAULT 200)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role text;
  v_limit integer := greatest(1, least(coalesce(_limit, 200), 500));
  result jsonb;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  SELECT role::text
    INTO v_role
    FROM public.profiles
   WHERE id = auth.uid();

  IF v_role IS NULL THEN
    RAISE EXCEPTION 'Staff profile required';
  END IF;

  IF v_role NOT IN (
    'admin',
    'practitioner',
    'nurse',
    'midwife',
    'specialist_nurse'
  ) THEN
    RAISE EXCEPTION 'Admission workspace access is not permitted';
  END IF;

  SELECT jsonb_build_object(
    'admissions',
    coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb)
  )
  INTO result
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
    JOIN public.patients p ON p.id = a.patient_id
    WHERE p.status <> 'inactive'
    ORDER BY a.admitted_at DESC
    LIMIT v_limit
  ) x;

  RETURN result;
END;
$$;

REVOKE ALL ON FUNCTION public.get_admission_workspace(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_admission_workspace(integer) TO authenticated;

-- The anonymous role has no legitimate admissions use case.
REVOKE SELECT ON TABLE public.admissions FROM anon;
