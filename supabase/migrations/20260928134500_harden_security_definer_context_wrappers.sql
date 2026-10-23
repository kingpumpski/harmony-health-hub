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

-- The active-facility relation is required by the resolver and by later
-- facility-governance migrations, but was absent from clean migration replay.
CREATE TABLE IF NOT EXISTS public.user_active_facilities (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  facility_id uuid NOT NULL REFERENCES public.healthcare_facilities(id) ON DELETE CASCADE,
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.user_active_facilities ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS user_active_facilities_select_own
  ON public.user_active_facilities;
CREATE POLICY user_active_facilities_select_own
  ON public.user_active_facilities
  FOR SELECT TO authenticated
  USING (
    user_id = (SELECT auth.uid())
    OR (SELECT public.has_role((SELECT auth.uid()), 'system_superuser'::public.app_role))
  );

-- Define the facility resolver before wrappers and later migrations depend on it.
-- The canonical facility-control-plane migration reasserts this implementation.
CREATE OR REPLACE FUNCTION public.current_user_facility_id()
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT COALESCE(
    (
      SELECT uaf.facility_id
      FROM public.user_active_facilities AS uaf
      JOIN public.facility_memberships AS fm
        ON fm.user_id = uaf.user_id
       AND fm.facility_id = uaf.facility_id
       AND fm.is_active = true
      WHERE uaf.user_id = (SELECT auth.uid())
        AND EXISTS (
          SELECT 1
          FROM public.healthcare_facilities AS hf
          WHERE hf.id = uaf.facility_id
            AND hf.is_active = true
        )
      LIMIT 1
    ),
    (
      SELECT fm.facility_id
      FROM public.facility_memberships AS fm
      JOIN public.healthcare_facilities AS hf
        ON hf.id = fm.facility_id
       AND hf.is_active = true
      WHERE fm.user_id = (SELECT auth.uid())
        AND fm.is_active = true
      GROUP BY fm.facility_id
      HAVING count(*) = 1
      ORDER BY fm.facility_id
      LIMIT 1
    )
  );
$function$;

REVOKE ALL ON FUNCTION public.current_user_facility_id() FROM PUBLIC, anon, authenticated;

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
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $function$
  SELECT
    hf.id,
    hf.name,
    hf.facility_code,
    hf.facility_type,
    hf.district,
    hf.region,
    hf.dhims2_uid,
    COALESCE(fc.timezone,'Africa/Accra'),
    COALESCE(fc.currency,'GHS')
  FROM public.healthcare_facilities hf
  LEFT JOIN public.facility_configuration fc ON true
  WHERE hf.id = public.current_user_facility_id()
    AND hf.is_active = true
    AND auth.uid() IS NOT NULL
  LIMIT 1;
$function$;

REVOKE ALL ON FUNCTION public.get_appointment_clinician() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_appointment_clinician() TO authenticated;

REVOKE ALL ON FUNCTION public.get_current_facility_context() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_current_facility_context() TO authenticated;
