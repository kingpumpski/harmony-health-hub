-- Permission lookup is a security boundary. SECURITY DEFINER prevents the
-- RLS policy from recursively querying hms_role_module_permissions itself.
CREATE OR REPLACE FUNCTION public.hms_has_module_permission(
  _module_code text, _action text, _user_id uuid DEFAULT auth.uid()
)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
  SELECT CASE
    WHEN public.has_role(_user_id,'admin'::public.app_role) THEN true
    ELSE COALESCE((
      SELECT CASE lower(_action)
        WHEN 'read' THEN p.can_read
        WHEN 'write' THEN p.can_write
        WHEN 'approve' THEN p.can_approve
        WHEN 'configure' THEN p.can_configure
        ELSE false
      END
      FROM public.hms_role_module_permissions p
      WHERE p.role_code = public.hms_current_role_code(_user_id)
        AND p.module_code = _module_code
    ),false)
  END;
$$;

REVOKE ALL ON FUNCTION public.hms_has_module_permission(text,text,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.hms_has_module_permission(text,text,uuid) TO authenticated;

COMMENT ON FUNCTION public.hms_has_module_permission(text,text,uuid)
IS 'Security-definer permission lookup to avoid recursive RLS evaluation. Existing user_roles remains the identity authority.';
