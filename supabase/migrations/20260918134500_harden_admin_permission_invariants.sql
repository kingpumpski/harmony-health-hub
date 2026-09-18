-- Administrators are the permanent full-access system role.
-- This keeps onboarding/support capability intact even when new permissions are introduced later.
CREATE OR REPLACE FUNCTION public.get_my_permissions()
RETURNS TABLE(permission_key TEXT)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path=public
AS $$
  SELECT p.permission_key
  FROM public.permissions p
  WHERE p.is_active
    AND EXISTS (
      SELECT 1 FROM public.user_roles ur
      WHERE ur.user_id=auth.uid() AND ur.role='admin'
    )
  UNION
  SELECT rp.permission_key
  FROM public.role_permissions rp
  JOIN public.permissions p ON p.permission_key=rp.permission_key
  JOIN public.user_roles ur ON ur.role=rp.role
  WHERE ur.user_id=auth.uid() AND p.is_active
    AND NOT EXISTS (
      SELECT 1 FROM public.user_roles admin_check
      WHERE admin_check.user_id=auth.uid() AND admin_check.role='admin'
    )
  ORDER BY permission_key;
$$;
REVOKE ALL ON FUNCTION public.get_my_permissions() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_permissions() TO authenticated;

CREATE OR REPLACE FUNCTION public.replace_role_permissions(
  _role public.app_role,
  _permission_keys TEXT[]
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public
AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT public.has_role(auth.uid(), 'admin') THEN
    RAISE EXCEPTION 'Administrator access required';
  END IF;
  IF _permission_keys IS NULL THEN
    RAISE EXCEPTION 'Permission list is required';
  END IF;
  IF _role='admin' THEN
    DELETE FROM public.role_permissions WHERE role='admin';
    INSERT INTO public.role_permissions(role,permission_key)
    SELECT 'admin', permission_key FROM public.permissions WHERE is_active
    ON CONFLICT DO NOTHING;
    RETURN TRUE;
  END IF;
  IF EXISTS (
    SELECT 1 FROM unnest(_permission_keys) requested(permission_key)
    LEFT JOIN public.permissions p ON p.permission_key=requested.permission_key AND p.is_active
    WHERE p.permission_key IS NULL
  ) THEN
    RAISE EXCEPTION 'One or more requested permissions are invalid or inactive';
  END IF;
  DELETE FROM public.role_permissions WHERE role=_role;
  INSERT INTO public.role_permissions(role,permission_key)
  SELECT _role, permission_key FROM unnest(_permission_keys) AS requested(permission_key)
  ON CONFLICT DO NOTHING;
  RETURN TRUE;
END;
$$;
REVOKE ALL ON FUNCTION public.replace_role_permissions(public.app_role,TEXT[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.replace_role_permissions(public.app_role,TEXT[]) TO authenticated;
