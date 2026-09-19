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



-- Bridge the broader role catalogue to the existing authoritative app_role/user_roles
-- system. This is additive: user_roles remains the identity/assignment authority.
CREATE OR REPLACE FUNCTION public.hms_role_code_for_app_role(_role text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $
  SELECT CASE _role
    WHEN 'admin' THEN 'super_admin'
    WHEN 'practitioner' THEN 'doctor'
    WHEN 'specialist_nurse' THEN 'nurse'
    WHEN 'nurse' THEN 'nurse'
    WHEN 'midwife' THEN 'midwife'
    WHEN 'lab_technician' THEN 'lab_scientist'
    WHEN 'pharmacist' THEN 'pharmacist'
    WHEN 'accountant' THEN 'billing_clerk'
    WHEN 'front_desk' THEN 'receptionist'
    WHEN 'canteen' THEN 'restaurant_manager'
    WHEN 'patient' THEN 'patient'
    ELSE NULL
  END;
$;

CREATE OR REPLACE FUNCTION public.hms_user_has_module_permission(
  _module_code text,
  _action text,
  _user_id uuid DEFAULT auth.uid()
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $
  SELECT
    EXISTS (
      SELECT 1
      FROM public.user_roles ur
      JOIN public.hms_role_module_permissions p
        ON p.role_code = public.hms_role_code_for_app_role(ur.role::text)
       AND p.module_code = _module_code
      WHERE ur.user_id = _user_id
        AND CASE _action
          WHEN 'read' THEN p.can_read
          WHEN 'write' THEN p.can_write
          WHEN 'approve' THEN p.can_approve
          WHEN 'configure' THEN p.can_configure
          ELSE false
        END
    )
    OR public.has_role(_user_id, 'admin'::public.app_role);
$;

CREATE OR REPLACE FUNCTION public.hms_assert_module_access(
  _facility_id uuid,
  _module_id text,
  _action text DEFAULT 'read'
)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $
DECLARE
  v_module_code text;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING errcode = '42501';
  END IF;

  IF NOT public.has_facility_access(auth.uid(), _facility_id) THEN
    RAISE EXCEPTION 'Facility access denied' USING errcode = '42501';
  END IF;

  PERFORM public.hms_assert_module_enabled(_facility_id, _module_id);

  SELECT module_code INTO v_module_code
  FROM public.hms_module_catalog
  WHERE module_id = _module_id;

  IF v_module_code IS NULL THEN
    RAISE EXCEPTION 'Unknown HMS module: %', _module_id;
  END IF;

  IF NOT public.hms_user_has_module_permission(v_module_code, _action, auth.uid()) THEN
    RAISE EXCEPTION 'HMS module permission denied: % %', _action, _module_id USING errcode = '42501';
  END IF;
END;
$;

REVOKE ALL ON FUNCTION public.hms_role_code_for_app_role(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.hms_user_has_module_permission(text,text,uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.hms_assert_module_access(uuid,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.hms_role_code_for_app_role(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.hms_user_has_module_permission(text,text,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.hms_assert_module_access(uuid,text,text) TO authenticated;

-- Safe baseline permissions for roles that already exist in the canonical
-- application. Administrators remain governed by the existing admin invariant.
INSERT INTO public.hms_role_module_permissions(role_code,module_code,can_read,can_write,can_approve,can_configure,scope_code)
VALUES
 ('doctor','M1',true,true,true,false,'facility'),('doctor','M3',true,true,true,false,'facility'),('doctor','M4',true,true,false,false,'facility'),('doctor','M5',true,true,false,false,'facility'),('doctor','M15',true,true,true,false,'facility'),
 ('nurse','M1',true,true,false,false,'facility'),('nurse','M3',true,true,false,false,'facility'),('nurse','M12',true,true,false,false,'facility'),('nurse','M14',true,true,false,false,'facility'),
 ('midwife','M1',true,true,false,false,'facility'),('midwife','M3',true,true,false,false,'facility'),('midwife','M9',true,true,false,false,'facility'),('midwife','M10',true,true,false,false,'facility'),
 ('lab_scientist','M1',true,false,false,false,'facility'),('lab_scientist','M5',true,true,true,false,'facility'),
 ('pharmacist','M1',true,false,false,false,'facility'),('pharmacist','M3',true,true,false,false,'facility'),('pharmacist','M4',true,true,true,false,'facility'),
 ('billing_clerk','M1',true,false,false,false,'facility'),('billing_clerk','M14',true,true,true,false,'facility'),('billing_clerk','M15',true,true,true,false,'facility'),
 ('receptionist','M1',true,true,false,false,'facility'),('receptionist','M2',true,true,false,false,'facility'),
 ('restaurant_manager','M13',true,true,true,false,'facility'),
 ('patient','M1',true,false,false,false,'self')
ON CONFLICT(role_code,module_code) DO UPDATE SET
 can_read=excluded.can_read,can_write=excluded.can_write,can_approve=excluded.can_approve,
 can_configure=excluded.can_configure,scope_code=excluded.scope_code;
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
