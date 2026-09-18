-- Runtime governance boundary for the broader HMS architecture.
-- Required enterprise modules are enabled by default; optional facility modules remain opt-in.
UPDATE public.hms_module_catalog
   SET default_enabled = CASE WHEN optional THEN false ELSE true END,
       updated_at = now()
 WHERE module_id IN ('physiotherapy','dietary-restaurant','teaching-research','asset-biomedical','procurement','data-import','report-centre','user-role-management');
-- This migration does not create a second RBAC system. It bridges the broader
-- role catalogue to the existing user_roles authority and makes facility
-- module enablement enforceable at server-side workflow boundaries.

CREATE OR REPLACE FUNCTION public.hms_current_role_code(_user_id uuid DEFAULT auth.uid())
RETURNS text
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT CASE
    WHEN EXISTS (SELECT 1 FROM public.user_roles ur WHERE ur.user_id = _user_id AND ur.role::text = 'admin') THEN 'super_admin'
    WHEN EXISTS (SELECT 1 FROM public.user_roles ur WHERE ur.user_id = _user_id AND ur.role::text = 'practitioner') THEN 'doctor'
    WHEN EXISTS (SELECT 1 FROM public.user_roles ur WHERE ur.user_id = _user_id AND ur.role::text = 'specialist_nurse') THEN 'nurse'
    WHEN EXISTS (SELECT 1 FROM public.user_roles ur WHERE ur.user_id = _user_id AND ur.role::text = 'lab_technician') THEN 'lab_scientist'
    WHEN EXISTS (SELECT 1 FROM public.user_roles ur WHERE ur.user_id = _user_id AND ur.role::text = 'accountant') THEN 'billing_clerk'
    WHEN EXISTS (SELECT 1 FROM public.user_roles ur WHERE ur.user_id = _user_id AND ur.role::text = 'front_desk') THEN 'receptionist'
    WHEN EXISTS (SELECT 1 FROM public.user_roles ur WHERE ur.user_id = _user_id AND ur.role::text = 'canteen') THEN 'restaurant_manager'
    WHEN EXISTS (SELECT 1 FROM public.user_roles ur WHERE ur.user_id = _user_id AND ur.role::text = 'patient') THEN 'patient'
    ELSE (SELECT ur.role::text FROM public.user_roles ur WHERE ur.user_id = _user_id ORDER BY ur.created_at ASC LIMIT 1)
  END;
$$;

CREATE OR REPLACE FUNCTION public.hms_module_is_enabled(_facility_id uuid, _module_id text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT COALESCE(
    (SELECT fm.enabled
       FROM public.hms_facility_modules fm
      WHERE fm.facility_id = _facility_id
        AND fm.module_id = _module_id
        AND (fm.effective_to IS NULL OR fm.effective_to > now())
      LIMIT 1),
    (SELECT mc.default_enabled
       FROM public.hms_module_catalog mc
      WHERE mc.module_id = _module_id),
    false
  );
$$;

CREATE OR REPLACE FUNCTION public.hms_assert_module_enabled(_facility_id uuid, _module_id text)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.hms_module_catalog WHERE module_id = _module_id) THEN
    RAISE EXCEPTION 'Unknown HMS module: %', _module_id;
  END IF;
  IF NOT public.hms_module_is_enabled(_facility_id, _module_id) THEN
    RAISE EXCEPTION 'HMS module % is disabled for this facility', _module_id;
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.hms_current_role_code(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.hms_module_is_enabled(uuid,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.hms_assert_module_enabled(uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.hms_current_role_code(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.hms_module_is_enabled(uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.hms_assert_module_enabled(uuid,text) TO authenticated;

-- Strengthen the module-management RPC: module configuration is itself
-- governed by the existing admin role, while all other modules remain
-- server-checked by hms_assert_module_enabled at their workflow boundary.
CREATE OR REPLACE FUNCTION public.set_hms_facility_module(_facility_id uuid,_module_id text,_enabled boolean)
RETURNS public.hms_facility_modules
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE r public.hms_facility_modules;
BEGIN
  IF auth.uid() IS NULL OR NOT public.has_role(auth.uid(),'admin'::public.app_role) THEN
    RAISE EXCEPTION 'Administrator authorization required';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.hms_module_catalog WHERE module_id = _module_id) THEN
    RAISE EXCEPTION 'Unknown HMS module';
  END IF;
  INSERT INTO public.hms_facility_modules(facility_id,module_id,enabled,configured_by)
  VALUES(_facility_id,_module_id,_enabled,auth.uid())
  ON CONFLICT(facility_id,module_id) DO UPDATE
    SET enabled=excluded.enabled,
        effective_from=now(),
        effective_to=NULL,
        configured_by=auth.uid(),
        configured_at=now()
  RETURNING * INTO r;
  RETURN r;
END;
$$;

REVOKE ALL ON FUNCTION public.set_hms_facility_module(uuid,text,boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.set_hms_facility_module(uuid,text,boolean) TO authenticated;

COMMENT ON FUNCTION public.hms_module_is_enabled(uuid,text)
IS 'Canonical server-side facility module gate. UI state is advisory; workflows must call the assert function before protected operations.';

COMMENT ON FUNCTION public.hms_assert_module_enabled(uuid,text)
IS 'Fail-closed module boundary for broader HMS workflows. Disabled facility modules cannot be used merely because a route is reachable.';
