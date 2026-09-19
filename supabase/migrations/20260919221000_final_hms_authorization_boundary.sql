-- Final authorization-boundary reconciliation.
-- 1. Every canonical HMS permission decision is facility-membership aware.
-- 2. The canonical user-role RPC cannot be used by an administrator to
--    demote their own account.
-- 3. Keep direct user_roles DML out of the authenticated API surface.

CREATE OR REPLACE FUNCTION private.hms_authorize(
  _user_id uuid,
  _facility_id uuid,
  _module_id text,
  _action text
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path=''
AS $$
  SELECT
    _user_id IS NOT NULL
    AND _facility_id IS NOT NULL
    AND public.has_facility_access(_user_id, _facility_id)
    AND EXISTS (
      SELECT 1
      FROM public.user_roles ur
      JOIN public.hms_app_role_map arm
        ON arm.app_role=ur.role::text
       AND arm.active=true
      JOIN public.hms_role_module_permissions p
        ON p.role_code=arm.role_code
      JOIN public.hms_module_catalog mc
        ON mc.module_code=p.module_code
      WHERE ur.user_id=_user_id
        AND mc.module_id=_module_id
        AND p.scope_code IN ('facility','global')
        AND public.hms_module_is_enabled(_facility_id,_module_id)
        AND (
          (lower(_action)='read' AND p.can_read)
          OR (lower(_action)='write' AND p.can_write)
          OR (lower(_action)='approve' AND p.can_approve)
          OR (lower(_action)='configure' AND p.can_configure)
        )
    );
$$;

REVOKE ALL ON FUNCTION private.hms_authorize(uuid,uuid,text,text) FROM PUBLIC,anon;
GRANT USAGE ON SCHEMA private TO authenticated;
GRANT EXECUTE ON FUNCTION private.hms_authorize(uuid,uuid,text,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.hms_user_has_module_permission(
  _module_code text,
  _action text,
  _user_id uuid DEFAULT auth.uid()
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path=''
AS $$
  SELECT
    auth.uid() IS NOT NULL
    AND _user_id = auth.uid()
    AND (
      public.has_role(auth.uid(),'admin'::public.app_role)
      OR EXISTS (
        SELECT 1
        FROM public.user_roles ur
        JOIN public.hms_role_module_permissions p
          ON p.role_code = public.hms_role_code_for_app_role(ur.role::text)
         AND p.module_code = _module_code
        WHERE ur.user_id = auth.uid()
          AND CASE lower(_action)
            WHEN 'read' THEN p.can_read
            WHEN 'write' THEN p.can_write
            WHEN 'approve' THEN p.can_approve
            WHEN 'configure' THEN p.can_configure
            ELSE false
          END
      )
    );
$$;

REVOKE ALL ON FUNCTION public.hms_user_has_module_permission(text,text,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.hms_user_has_module_permission(text,text,uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.set_hms_user_role(_target_user_id uuid, _role text)
RETURNS public.user_roles
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public
AS $$
DECLARE
  result_row public.user_roles;
  target_is_admin boolean;
BEGIN
  IF auth.uid() IS NULL OR NOT public.has_role(auth.uid(), 'admin'::public.app_role) THEN
    RAISE EXCEPTION 'Administrator authorization required' USING ERRCODE='42501';
  END IF;

  IF _target_user_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM auth.users WHERE id=_target_user_id
  ) THEN
    RAISE EXCEPTION 'Target user does not exist';
  END IF;

  IF _role IS NULL OR _role NOT IN (
    'admin','practitioner','nurse','midwife','lab_technician',
    'pharmacist','accountant','front_desk','canteen','patient'
  ) THEN
    RAISE EXCEPTION 'Unsupported HMS application role';
  END IF;

  -- Administrators may not use the role-management RPC to remove their own
  -- administrative authority. Another administrator must perform that change,
  -- and the final administrator remains protected below.
  IF _target_user_id = auth.uid() AND _role <> 'admin' THEN
    RAISE EXCEPTION 'Administrators cannot demote themselves' USING ERRCODE='42501';
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM public.user_roles
    WHERE user_id=_target_user_id
      AND role='admin'::public.app_role
  ) INTO target_is_admin;

  IF target_is_admin AND _role <> 'admin'
     AND (SELECT count(*) FROM public.user_roles WHERE role='admin'::public.app_role) <= 1 THEN
    RAISE EXCEPTION 'The final administrator cannot be demoted' USING ERRCODE='42501';
  END IF;

  DELETE FROM public.user_roles WHERE user_id=_target_user_id;
  INSERT INTO public.user_roles(user_id,role)
  VALUES (_target_user_id,_role::public.app_role)
  RETURNING * INTO result_row;

  RETURN result_row;
END;
$$;

REVOKE ALL ON FUNCTION public.set_hms_user_role(uuid,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.set_hms_user_role(uuid,text) TO authenticated;

-- Authenticated clients must use governed RPCs rather than direct role-table DML.
REVOKE INSERT,UPDATE,DELETE ON TABLE public.user_roles FROM authenticated;
REVOKE INSERT,UPDATE,DELETE ON TABLE public.user_roles FROM anon;

COMMENT ON FUNCTION public.set_hms_user_role(uuid,text)
IS 'Canonical administrator-controlled role assignment. Self-demotion and final-administrator demotion are blocked; direct authenticated DML on user_roles is revoked.';

COMMENT ON FUNCTION private.hms_authorize(uuid,uuid,text,text)
IS 'Canonical HMS authorization bridge. Requires authenticated identity, facility membership, enabled module and role/module/action permission.';
