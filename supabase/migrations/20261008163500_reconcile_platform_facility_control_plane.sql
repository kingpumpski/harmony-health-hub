-- Platform facility control-plane reconciliation for system superusers.
-- System superusers are platform-scoped and therefore do not require a facility
-- membership merely to enumerate or onboard facilities.

BEGIN;

CREATE OR REPLACE FUNCTION public.platform_list_facilities()
RETURNS TABLE(
  id uuid,name text,facility_code text,facility_type text,
  district text,region text,is_active boolean,created_at timestamptz
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=''
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.user_roles ur
    WHERE ur.user_id=(SELECT auth.uid())
      AND ur.role='system_superuser'::public.app_role
  ) THEN
    RAISE EXCEPTION 'Only system super administrators may view platform facilities';
  END IF;
  RETURN QUERY
  SELECT hf.id,hf.name,hf.facility_code,hf.facility_type,hf.district,hf.region,hf.is_active,hf.created_at
  FROM public.healthcare_facilities hf
  ORDER BY hf.created_at DESC;
END;
$$;

CREATE OR REPLACE FUNCTION public.platform_list_facilitys()
RETURNS TABLE(
  id uuid,name text,facility_code text,facility_type text,
  district text,region text,is_active boolean,created_at timestamptz
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=''
AS $$
BEGIN
  RETURN QUERY SELECT * FROM public.platform_list_facilities();
END;
$$;

CREATE OR REPLACE FUNCTION public.platform_create_facility(
  _name text,
  _facility_code text DEFAULT NULL,
  _facility_type text DEFAULT 'district_hospital',
  _district text DEFAULT NULL,
  _region text DEFAULT NULL,
  _dhims2_uid text DEFAULT NULL
)
RETURNS public.healthcare_facilities
LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
DECLARE
  v_user uuid := (SELECT auth.uid());
  v_facility public.healthcare_facilities;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.user_roles ur
    WHERE ur.user_id=v_user AND ur.role='system_superuser'::public.app_role
  ) THEN
    RAISE EXCEPTION 'Only system super administrators may onboard facilities';
  END IF;
  IF nullif(btrim(coalesce(_name,'')),'') IS NULL THEN
    RAISE EXCEPTION 'Facility name is required';
  END IF;
  IF _facility_type NOT IN (
    'chps_compound','health_centre','district_hospital','regional_hospital',
    'teaching_hospital','specialist_hospital','polyclinic','clinic',
    'maternity_home','other'
  ) THEN
    RAISE EXCEPTION 'Unsupported facility type';
  END IF;

  IF nullif(btrim(_facility_code),'') IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.healthcare_facilities hf
    WHERE hf.facility_code=nullif(btrim(_facility_code),'')
  ) THEN
    RAISE EXCEPTION 'Facility code already exists' USING errcode='23505';
  END IF;

  INSERT INTO public.healthcare_facilities(
    name,facility_code,facility_type,district,region,dhims2_uid,created_by
  )
  VALUES(
    btrim(_name),nullif(btrim(_facility_code),''),_facility_type,
    nullif(btrim(_district),''),nullif(btrim(_region),''),
    nullif(btrim(_dhims2_uid),''),v_user
  )
  RETURNING * INTO v_facility;

  INSERT INTO public.hms_facility_modules(
    facility_id,module_id,enabled,service_available,readiness_status,configured_by
  )
  SELECT v_facility.id,m.module_id,false,false,'not_available',v_user
  FROM public.hms_module_catalog m
  ON CONFLICT (facility_id,module_id) DO NOTHING;

  INSERT INTO public.system_audit_log(
    actor_id,action,module,entity_type,entity_id,severity,metadata
  ) VALUES (
    v_user,'facility_onboarded','platform','facility',v_facility.id,'info',
    jsonb_build_object('facility_code',v_facility.facility_code,'facility_type',v_facility.facility_type)
  );
  BEGIN
    PERFORM public.seed_facility_reports(v_facility.id);
  EXCEPTION WHEN undefined_function THEN
    NULL;
  END;
  RETURN v_facility;
END;
$$;

REVOKE ALL ON FUNCTION public.platform_list_facilities() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.platform_list_facilitys() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.platform_create_facility(text,text,text,text,text,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.platform_list_facilities() TO authenticated;
GRANT EXECUTE ON FUNCTION public.platform_list_facilitys() TO authenticated;
GRANT EXECUTE ON FUNCTION public.platform_create_facility(text,text,text,text,text,text) TO authenticated;

NOTIFY pgrst,'reload schema';
COMMIT;
