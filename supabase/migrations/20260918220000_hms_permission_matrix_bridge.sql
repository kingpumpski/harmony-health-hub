-- Bridge the broader role matrix to the existing user_roles authority.
-- hms_role_catalog/hms_role_module_permissions are policy metadata; user_roles
-- remains the authoritative assignment table until a dedicated provisioning
-- workflow is introduced and approved.

CREATE OR REPLACE FUNCTION public.hms_role_codes_for_user(_user_id uuid DEFAULT auth.uid())
RETURNS TABLE(role_code text)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT DISTINCT mapped.role_code
  FROM public.user_roles ur
  CROSS JOIN LATERAL (
    VALUES
      (CASE WHEN ur.role::text = 'admin' THEN 'super_admin' END),
      (CASE WHEN ur.role::text = 'practitioner' THEN 'doctor' END),
      (CASE WHEN ur.role::text = 'nurse' THEN 'nurse' END),
      (CASE WHEN ur.role::text = 'midwife' THEN 'midwife' END),
      (CASE WHEN ur.role::text = 'lab_technician' THEN 'lab_scientist' END),
      (CASE WHEN ur.role::text = 'pharmacist' THEN 'pharmacist' END),
      (CASE WHEN ur.role::text = 'accountant' THEN 'billing_clerk' END),
      (CASE WHEN ur.role::text = 'front_desk' THEN 'receptionist' END),
      (CASE WHEN ur.role::text = 'canteen' THEN 'restaurant_manager' END),
      (CASE WHEN ur.role::text = 'patient' THEN 'patient' END)
  ) mapped(role_code)
  WHERE ur.user_id = COALESCE(_user_id, auth.uid())
    AND mapped.role_code IS NOT NULL;
$$;

CREATE OR REPLACE FUNCTION public.hms_user_can(
  _facility_id uuid,
  _module_id text,
  _action text,
  _user_id uuid DEFAULT auth.uid()
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT
    auth.uid() IS NOT NULL
    AND _user_id = auth.uid()
    AND public.hms_module_is_enabled(_facility_id, _module_id)
    AND (
      public.has_role(auth.uid(), 'admin'::public.app_role)
      OR EXISTS (
        SELECT 1
        FROM public.hms_role_codes_for_user(auth.uid()) rc
        JOIN public.hms_role_module_permissions p
          ON p.role_code = rc.role_code
        WHERE p.module_code IN (
          _module_id,
          COALESCE((SELECT module_code FROM public.hms_module_catalog WHERE module_id = _module_id), '')
        )
        AND (
          (_action = 'read' AND p.can_read)
          OR (_action = 'write' AND p.can_write)
          OR (_action = 'approve' AND p.can_approve)
          OR (_action = 'configure' AND p.can_configure)
        )
      )
    );
$$;

CREATE OR REPLACE FUNCTION public.hms_assert_user_can(
  _facility_id uuid,
  _module_id text,
  _action text,
  _user_id uuid DEFAULT auth.uid()
)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
BEGIN
  IF NOT public.hms_user_can(_facility_id, _module_id, _action, _user_id) THEN
    RAISE EXCEPTION 'HMS authorization denied for module % action %', _module_id, _action
      USING ERRCODE = '42501';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.hms_role_codes_for_user(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.hms_user_can(uuid,text,text,uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.hms_assert_user_can(uuid,text,text,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.hms_role_codes_for_user(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.hms_user_can(uuid,text,text,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.hms_assert_user_can(uuid,text,text,uuid) TO authenticated;

-- Seed explicit module-id aliases alongside the legacy M1-M25 rows. This keeps
-- the matrix consumable by both the broader contract and existing screens.
INSERT INTO public.hms_role_module_permissions(role_code,module_code)
SELECT r.role_code, m.module_id
FROM public.hms_role_catalog r
CROSS JOIN public.hms_module_catalog m
ON CONFLICT DO NOTHING;

-- Administrator is the existing full-access authority. Other mapped roles
-- remain least-privilege until their exact matrix is configured by an admin.
UPDATE public.hms_role_module_permissions
SET can_read = true, can_write = true, can_approve = true, can_configure = true, scope_code = 'facility'
WHERE role_code = 'super_admin';

COMMENT ON FUNCTION public.hms_user_can(uuid,text,text,uuid)
IS 'Canonical broader HMS authorization evaluator. Facility module enablement is checked before role permission; existing user_roles remains authoritative for assignment.';
