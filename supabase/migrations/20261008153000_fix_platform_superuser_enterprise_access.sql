-- Correct platform-wide authorization for System Super Users.
-- Facility membership remains mandatory for every other user.
CREATE OR REPLACE FUNCTION public.hms_user_can(
  _facility_id uuid,
  _module_id text,
  _action text,
  _user_id uuid DEFAULT auth.uid()
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path=public
AS $$
  SELECT auth.uid() IS NOT NULL
    AND _user_id = auth.uid()
    AND (
      public.has_role(_user_id,'system_superuser'::public.app_role)
      OR public.has_facility_access(_user_id,_facility_id)
    )
    AND public.hms_module_is_enabled(_facility_id,_module_id)
    AND (
      public.has_role(_user_id,'admin'::public.app_role)
      OR public.has_role(_user_id,'system_superuser'::public.app_role)
      OR EXISTS (
        SELECT 1
        FROM public.hms_role_codes_for_user(_user_id) rc
        JOIN public.hms_role_module_permissions p ON p.role_code=rc.role_code
        JOIN public.hms_module_catalog m ON m.module_code=p.module_code OR m.module_id=p.module_code
        WHERE m.module_id=_module_id
          AND CASE lower(_action)
            WHEN 'read' THEN p.can_read
            WHEN 'write' THEN p.can_write
            WHEN 'approve' THEN p.can_approve
            WHEN 'configure' THEN p.can_configure
            ELSE false
          END
      )
      OR EXISTS (
        SELECT 1
        FROM public.hms_user_role_assignments a
        JOIN public.hms_role_module_permissions p ON p.role_code=a.role_code
        JOIN public.hms_module_catalog m ON m.module_code=p.module_code OR m.module_id=p.module_code
        WHERE a.user_id=_user_id
          AND a.facility_id=_facility_id
          AND a.active=true
          AND a.effective_from<=now()
          AND (a.effective_to IS NULL OR a.effective_to>now())
          AND m.module_id=_module_id
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

REVOKE ALL ON FUNCTION public.hms_user_can(uuid,text,text,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.hms_user_can(uuid,text,text,uuid) TO authenticated;

COMMENT ON FUNCTION public.hms_user_can(uuid,text,text,uuid) IS
'Canonical facility-scoped authorization. System Super Users may troubleshoot platform-wide without facility membership; all other users require facility access.';
