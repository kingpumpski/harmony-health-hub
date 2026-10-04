-- Complete platform facility onboarding with notification bootstrap.
CREATE OR REPLACE FUNCTION public.initialize_facility_notification_onboarding(_facility_id uuid)
RETURNS public.facility_notification_config
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE v public.facility_notification_config;
BEGIN
  IF auth.uid() IS NULL
     OR NOT (
       public.has_role(auth.uid(),'admin'::public.app_role)
       OR public.has_role(auth.uid(),'it_admin'::public.app_role)
       OR public.has_role(auth.uid(),'system_superuser'::public.app_role)
     )
     OR NOT (
       public.has_role(auth.uid(),'system_superuser'::public.app_role)
       OR public.has_facility_access(auth.uid(),_facility_id)
     ) THEN
    RAISE EXCEPTION 'Facility notification onboarding requires authorized platform or facility administrator access';
  END IF;
  INSERT INTO public.facility_notification_config(facility_id,created_by,updated_by)
  VALUES(_facility_id,auth.uid(),auth.uid())
  ON CONFLICT(facility_id) DO UPDATE SET updated_at=now(),updated_by=auth.uid()
  RETURNING * INTO v;
  RETURN v;
END
$function$;

CREATE OR REPLACE FUNCTION public.platform_create_facility(
  _name text,
  _facility_code text DEFAULT NULL,
  _facility_type text DEFAULT 'district_hospital',
  _district text DEFAULT NULL,
  _region text DEFAULT NULL,
  _dhims2_uid text DEFAULT NULL
)
RETURNS public.healthcare_facilities
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_user uuid := (select auth.uid());
  v_facility public.healthcare_facilities;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.user_roles ur
    WHERE ur.user_id=v_user AND ur.role='system_superuser'::public.app_role
  ) THEN
    RAISE EXCEPTION 'Only system super administrators may onboard facilities';
  END IF;
  IF nullif(btrim(coalesce(_name,'')),'') IS NULL THEN RAISE EXCEPTION 'Facility name is required'; END IF;
  IF _facility_type NOT IN ('chps_compound','health_centre','district_hospital','regional_hospital','teaching_hospital','specialist_hospital','polyclinic','clinic','maternity_home','other') THEN
    RAISE EXCEPTION 'Unsupported facility type';
  END IF;

  INSERT INTO public.healthcare_facilities(name,facility_code,facility_type,district,region,dhims2_uid,created_by)
  VALUES(btrim(_name),nullif(btrim(_facility_code),''),_facility_type,nullif(btrim(_district),''),nullif(btrim(_region),''),nullif(btrim(_dhims2_uid),''),v_user)
  RETURNING * INTO v_facility;

  PERFORM public.initialize_facility_notification_onboarding(v_facility.id);
  BEGIN
    PERFORM public.seed_facility_reports(v_facility.id);
  EXCEPTION WHEN undefined_function THEN
    NULL;
  END;
  RETURN v_facility;
END
$function$;

REVOKE ALL ON FUNCTION public.initialize_facility_notification_onboarding(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.initialize_facility_notification_onboarding(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.platform_create_facility(text,text,text,text,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.platform_create_facility(text,text,text,text,text,text) TO authenticated;
NOTIFY pgrst,'reload schema';