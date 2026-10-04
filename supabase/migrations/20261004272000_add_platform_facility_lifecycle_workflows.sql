CREATE OR REPLACE FUNCTION public.platform_update_facility(_facility_id uuid,_name text,_facility_code text,_facility_type text,_district text,_region text,_dhims2_uid text)
RETURNS public.healthcare_facilities
LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
DECLARE v public.healthcare_facilities;
BEGIN
 IF auth.uid() IS NULL OR NOT public.has_role(auth.uid(),'system_superuser'::public.app_role) THEN RAISE EXCEPTION 'Only system super administrators may update facilities'; END IF;
 IF nullif(btrim(coalesce(_name,'')),'') IS NULL THEN RAISE EXCEPTION 'Facility name is required'; END IF;
 IF _facility_type NOT IN ('chps_compound','health_centre','district_hospital','regional_hospital','teaching_hospital','specialist_hospital','polyclinic','clinic','maternity_home','other') THEN RAISE EXCEPTION 'Unsupported facility type'; END IF;
 UPDATE public.healthcare_facilities SET name=btrim(_name),facility_code=nullif(btrim(coalesce(_facility_code,'')),''),facility_type=_facility_type,district=nullif(btrim(coalesce(_district,'')),''),region=nullif(btrim(coalesce(_region,'')),''),dhims2_uid=nullif(btrim(coalesce(_dhims2_uid,'')),''),updated_at=now() WHERE id=_facility_id RETURNING * INTO v;
 IF NOT FOUND THEN RAISE EXCEPTION 'Facility not found'; END IF;
 RETURN v;
END $$;

CREATE OR REPLACE FUNCTION public.platform_set_facility_active(_facility_id uuid,_is_active boolean)
RETURNS public.healthcare_facilities
LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
DECLARE v public.healthcare_facilities;
BEGIN
 IF auth.uid() IS NULL OR NOT public.has_role(auth.uid(),'system_superuser'::public.app_role) THEN RAISE EXCEPTION 'Only system super administrators may change facility status'; END IF;
 IF _is_active IS FALSE AND EXISTS (SELECT 1 FROM public.user_active_facilities WHERE facility_id=_facility_id) THEN RAISE EXCEPTION 'Facility cannot be deactivated while users still have it as their active facility context'; END IF;
 UPDATE public.healthcare_facilities SET is_active=_is_active,updated_at=now() WHERE id=_facility_id RETURNING * INTO v;
 IF NOT FOUND THEN RAISE EXCEPTION 'Facility not found'; END IF;
 RETURN v;
END $$;

REVOKE ALL ON FUNCTION public.platform_update_facility(uuid,text,text,text,text,text,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.platform_update_facility(uuid,text,text,text,text,text,text) TO authenticated;
REVOKE ALL ON FUNCTION public.platform_set_facility_active(uuid,boolean) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.platform_set_facility_active(uuid,boolean) TO authenticated;
NOTIFY pgrst,'reload schema';