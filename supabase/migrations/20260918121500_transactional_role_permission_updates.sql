-- Transactional administrator role-permission replacement.
-- Navigation permissions are additive UI configuration; existing RLS/RPC role checks remain authoritative.

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

  IF EXISTS (
    SELECT 1
    FROM unnest(_permission_keys) requested(permission_key)
    LEFT JOIN public.permissions p ON p.permission_key = requested.permission_key AND p.is_active
    WHERE p.permission_key IS NULL
  ) THEN
    RAISE EXCEPTION 'One or more requested permissions are invalid or inactive';
  END IF;

  DELETE FROM public.role_permissions WHERE role = _role;

  INSERT INTO public.role_permissions(role, permission_key)
  SELECT _role, permission_key
  FROM unnest(_permission_keys) AS requested(permission_key)
  ON CONFLICT DO NOTHING;

  RETURN TRUE;
END;
$$;

REVOKE ALL ON FUNCTION public.replace_role_permissions(public.app_role, TEXT[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.replace_role_permissions(public.app_role, TEXT[]) TO authenticated;
