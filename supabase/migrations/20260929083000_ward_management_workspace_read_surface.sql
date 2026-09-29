BEGIN;

CREATE OR REPLACE FUNCTION public.get_ward_management_workspace(_limit integer DEFAULT 500)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $function$
DECLARE
  uid uuid := auth.uid();
  v_role text;
  v_facility uuid := public.current_user_facility_id();
  v_limit integer := greatest(1,least(coalesce(_limit,500),1000));
  result jsonb;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  SELECT ur.role::text INTO v_role
  FROM public.user_roles ur
  WHERE ur.user_id=uid
  ORDER BY ur.created_at DESC
  LIMIT 1;

  IF v_role NOT IN ('admin','it_admin','practitioner','nurse','midwife','specialist_nurse') THEN
    RAISE EXCEPTION 'Not authorised';
  END IF;

  SELECT jsonb_build_object(
    'wards',COALESCE((
      SELECT jsonb_agg(to_jsonb(x)) FROM (
        SELECT w.id,w.name,w.code,w.specialty,w.gender_policy,w.active,w.facility_id,
               hf.name AS facility_name
        FROM public.ward_units w
        LEFT JOIN public.healthcare_facilities hf ON hf.id=w.facility_id
        WHERE (v_role IN ('admin','it_admin') OR w.facility_id IS NULL OR w.facility_id=v_facility)
        ORDER BY hf.name NULLS LAST,w.name
        LIMIT v_limit
      ) x
    ),'[]'::jsonb),
    'beds',COALESCE((
      SELECT jsonb_agg(to_jsonb(x)) FROM (
        SELECT b.id,b.ward_id,b.bed_number,b.status,b.patient_id,b.admission_id,b.facility_id
        FROM public.ward_beds b
        WHERE (v_role IN ('admin','it_admin') OR b.facility_id IS NULL OR b.facility_id=v_facility)
        ORDER BY b.bed_number
        LIMIT v_limit
      ) x
    ),'[]'::jsonb),
    'facilities',CASE WHEN v_role IN ('admin','it_admin') THEN COALESCE((
      SELECT jsonb_agg(to_jsonb(x)) FROM (
        SELECT id,name,facility_code,facility_type,district,region,is_active
        FROM public.healthcare_facilities
        WHERE is_active=true
        ORDER BY name
      ) x
    ),'[]'::jsonb) ELSE '[]'::jsonb END
  ) INTO result;

  RETURN result;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_ward_management_workspace(integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_ward_management_workspace(integer) TO authenticated;

COMMIT;