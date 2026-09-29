BEGIN;

CREATE OR REPLACE FUNCTION public.initialize_facility_notification_onboarding(_facility_id uuid)
RETURNS public.facility_notification_config
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v public.facility_notification_config;
BEGIN
  IF auth.uid() IS NULL
     OR NOT (
       public.has_role(auth.uid(),'admin'::public.app_role)
       OR public.has_role(auth.uid(),'it_admin'::public.app_role)
     )
     OR NOT public.has_facility_access(auth.uid(),_facility_id) THEN
    RAISE EXCEPTION 'Facility notification onboarding requires administrator or IT administrator facility access';
  END IF;

  INSERT INTO public.facility_notification_config(facility_id,created_by,updated_by)
  VALUES(_facility_id,auth.uid(),auth.uid())
  ON CONFLICT(facility_id) DO UPDATE
    SET updated_at=now(),updated_by=auth.uid()
  RETURNING * INTO v;

  RETURN v;
END
$function$;

REVOKE ALL ON FUNCTION public.initialize_facility_notification_onboarding(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.initialize_facility_notification_onboarding(uuid) TO authenticated;

COMMIT;
