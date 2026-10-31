-- Harden SECURITY DEFINER context/lookup wrappers that are exposed through PostgREST.
-- They are authenticated application helpers, not anonymous/public endpoints.

CREATE OR REPLACE FUNCTION public.get_appointment_clinician()
RETURNS TABLE(
  id uuid,
  first_name text,
  last_name text,
  department text,
  specialization text,
  clinician_role text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $function$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;
  RETURN QUERY SELECT * FROM public.get_appointment_clinicians();
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_current_facility_context()
RETURNS TABLE(
  facility_id uuid,
  facility_name text,
  facility_code text,
  facility_type text,
  district text,
  region text,
  dhims2_uid text,
  timezone text,
  currency text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $function$
BEGIN
  -- This migration runs before current_user_facility_id() is installed.
  -- Resolve the single active membership without introducing a forward
  -- function dependency; the canonical facility-context migration replaces
  -- this transitional implementation later in the migration sequence.
  IF auth.uid() IS NULL
     OR to_regclass('public.facility_memberships') IS NULL THEN
    RETURN;
  END IF;

  RETURN QUERY EXECUTE
    'SELECT
       hf.id,
       hf.name,
       hf.facility_code,
       hf.facility_type,
       hf.district,
       hf.region,
       hf.dhims2_uid,
       COALESCE(fc.timezone, ''Africa/Accra''),
       COALESCE(fc.currency, ''GHS'')
     FROM public.healthcare_facilities hf
     LEFT JOIN public.facility_configuration fc ON true
     WHERE hf.id = (
       SELECT fm.facility_id
       FROM public.facility_memberships fm
       WHERE fm.user_id = $1
         AND fm.is_active = true
       GROUP BY fm.facility_id
       HAVING count(*) = 1
       ORDER BY fm.facility_id
       LIMIT 1
     )
       AND hf.is_active = true
     LIMIT 1'
  USING auth.uid();
END;
$function$;

REVOKE ALL ON FUNCTION public.get_appointment_clinician() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_appointment_clinician() TO authenticated;

REVOKE ALL ON FUNCTION public.get_current_facility_context() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_current_facility_context() TO authenticated;
