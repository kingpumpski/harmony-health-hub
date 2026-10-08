-- Enterprise facility onboarding compatibility migration.
-- The canonical facility entity is healthcare_facilities; the later
-- 20261008163500 reconciliation migration keeps the same platform-control
-- semantics while adding the final platform listing/compatibility wrappers.
--
-- Facility creation is a platform privilege, not a facility/module permission.
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
SET search_path=''
AS $$
DECLARE
  v_user uuid := (SELECT auth.uid());
  v_facility public.healthcare_facilities;
  v_code text := nullif(btrim(_facility_code), '');
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING errcode='42501';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.user_roles ur
    WHERE ur.user_id=v_user
      AND ur.role='system_superuser'::public.app_role
  ) THEN
    RAISE EXCEPTION 'Only system super administrators may onboard facilities' USING errcode='42501';
  END IF;
  IF nullif(btrim(coalesce(_name,'')), '') IS NULL THEN
    RAISE EXCEPTION 'Facility name is required' USING errcode='22023';
  END IF;
  IF _facility_type NOT IN (
    'chps_compound','health_centre','district_hospital','regional_hospital',
    'teaching_hospital','specialist_hospital','polyclinic','clinic',
    'maternity_home','other'
  ) THEN
    RAISE EXCEPTION 'Unsupported facility type' USING errcode='22023';
  END IF;
  IF v_code IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.healthcare_facilities hf WHERE hf.facility_code=v_code
  ) THEN
    RAISE EXCEPTION 'Facility code already exists' USING errcode='23505';
  END IF;

  INSERT INTO public.healthcare_facilities(
    name,facility_code,facility_type,district,region,dhims2_uid,created_by
  )
  VALUES(
    btrim(_name),v_code,_facility_type,
    nullif(btrim(_district),''),nullif(btrim(_region),''),
    nullif(btrim(_dhims2_uid),''),v_user
  )
  RETURNING * INTO v_facility;

  -- New facilities must never inherit an implicitly enabled enterprise module.
  -- The catalogue is seeded only after the facility exists; service declaration
  -- and module enablement remain separate, governed operations.
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
  RETURN v_facility;
END;
$$;

REVOKE ALL ON FUNCTION public.platform_create_facility(text,text,text,text,text,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.platform_create_facility(text,text,text,text,text,text) TO authenticated;

COMMENT ON FUNCTION public.platform_create_facility(text,text,text,text,text,text) IS
'Platform facility onboarding. Only system_superuser may create facilities. New facilities receive disabled/not-available module rows and require explicit service readiness before activation.';
