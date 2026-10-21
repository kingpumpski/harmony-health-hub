-- Compatibility overload for legacy policies that pass a role array.
-- The canonical scalar helper remains the source of role-membership truth.
CREATE OR REPLACE FUNCTION public.has_role(_user_id UUID, _roles public.app_role[])
RETURNS BOOLEAN
LANGUAGE SQL
STABLE
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM unnest(COALESCE(_roles, ARRAY[]::public.app_role[])) AS requested(role)
    WHERE public.has_role(_user_id, requested.role)
  );
$$;

REVOKE ALL ON FUNCTION public.has_role(UUID, public.app_role[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.has_role(UUID, public.app_role[]) TO authenticated, service_role;
