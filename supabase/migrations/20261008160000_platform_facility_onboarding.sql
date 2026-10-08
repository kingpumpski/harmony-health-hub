-- Enterprise facility onboarding: a platform-control operation, not a facility-role permission.
CREATE OR REPLACE FUNCTION public.platform_create_facility(
  _name text,
  _facility_code text DEFAULT NULL,
  _facility_type text DEFAULT 'hospital',
  _country_code text DEFAULT 'GH',
  _timezone text DEFAULT 'Africa/Accra'
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public
AS $$
DECLARE
  v_id uuid;
BEGIN
  IF auth.uid() IS NULL OR NOT public.has_role(auth.uid(), 'system_superuser'::public.app_role) THEN
    RAISE EXCEPTION 'Platform Super Admin permission is required to onboard facilities';
  END IF;
  IF nullif(trim(_name), '') IS NULL THEN
    RAISE EXCEPTION 'Facility name is required';
  END IF;
  IF _country_code IS NULL OR length(trim(_country_code)) <> 2 THEN
    RAISE EXCEPTION 'A valid ISO country code is required';
  END IF;

  INSERT INTO public.facilities(name, facility_code, facility_type, country_code, timezone, is_active)
  VALUES (trim(_name), nullif(trim(_facility_code), ''), lower(trim(_facility_type)), upper(trim(_country_code)), coalesce(nullif(trim(_timezone), ''), 'Africa/Accra'), true)
  RETURNING id INTO v_id;

  -- Seed the enterprise service catalogue through the canonical service-gating
  -- function when available. This does not enable modules automatically.
  INSERT INTO public.hms_facility_modules(facility_id, module_id, enabled, service_available, readiness_status)
  SELECT v_id, m.module_id, false, false, 'not_available'
  FROM public.hms_module_catalog m
  ON CONFLICT (facility_id, module_id) DO NOTHING;

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.platform_create_facility(text,text,text,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.platform_create_facility(text,text,text,text,text) TO authenticated;

COMMENT ON FUNCTION public.platform_create_facility(text,text,text,text,text) IS
'Enterprise facility onboarding control. Only system_superuser may create facilities; normal facility permissions never grant onboarding authority.';
