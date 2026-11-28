-- Align the admission workspace projection with the canonical patient/admission/bed facility chain.
-- Facility-scoped users must have an active facility; only system_superuser may cross facilities.
CREATE OR REPLACE FUNCTION public.get_admission_workspace(_limit integer DEFAULT 200)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_role text;
  v_facility uuid;
  v_platform_superuser boolean;
  v_limit integer := greatest(1, least(coalesce(_limit, 200), 500));
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  SELECT ur.role::text
  INTO v_role
  FROM public.user_roles ur
  WHERE ur.user_id = auth.uid()
  ORDER BY ur.created_at DESC
  LIMIT 1;

  v_platform_superuser := public.has_role(auth.uid(), 'system_superuser');
  IF v_role IS NULL AND NOT v_platform_superuser THEN
    RAISE EXCEPTION 'Staff profile required';
  END IF;

  IF NOT v_platform_superuser
     AND v_role NOT IN ('admin', 'practitioner', 'nurse', 'midwife', 'specialist_nurse') THEN
    RAISE EXCEPTION 'Admission workspace access is not permitted';
  END IF;

  v_facility := public.current_user_facility_id();
  IF NOT v_platform_superuser AND v_facility IS NULL THEN
    RAISE EXCEPTION 'Select an active facility to access the admission workspace';
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
      JOIN public.patients p ON p.id = a.patient_id
      WHERE p.status <> 'inactive'
        AND (
          v_platform_superuser
          OR (
            a.facility_id = v_facility
            AND p.facility_id = v_facility
            AND NOT EXISTS (
              SELECT 1
              FROM public.ward_beds b
              LEFT JOIN public.ward_units w ON w.id = b.ward_id
              WHERE b.admission_id = a.id
                AND (
                  b.facility_id IS DISTINCT FROM v_facility
                  OR (w.id IS NOT NULL AND w.facility_id IS DISTINCT FROM v_facility)
                )
            )
          )
        )
      ORDER BY a.admitted_at DESC
      LIMIT v_limit
    ) x
  ), '[]'::jsonb);
END;
$function$;

REVOKE ALL ON FUNCTION public.get_admission_workspace(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_admission_workspace(integer) TO authenticated;
NOTIFY pgrst, 'reload schema';
