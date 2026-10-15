-- Compatibility overloads for legacy enterprise HIMS policies.
-- Keep the existing single-role authorization helpers canonical; these overloads
-- preserve historical array-based policies until the later policy normalization
-- migration rewrites them. All checks are evaluated for the current user only.
CREATE OR REPLACE FUNCTION public.has_role(p_user_id uuid, p_roles public.app_role[])
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT p_user_id IS NOT NULL
     AND p_roles IS NOT NULL
     AND EXISTS (
       SELECT 1
       FROM unnest(p_roles) AS requested(role_code)
       WHERE public.has_role(p_user_id, requested.role_code)
     );
$$;

REVOKE ALL ON FUNCTION public.has_role(uuid, public.app_role[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.has_role(uuid, public.app_role[]) TO authenticated;

-- Some policy-normalization migrations replace has_role(auth.uid(), roles[])
-- with current_user_has_role(roles[]). Provide a safe array overload while
-- preserving the established single-role helper as the source of truth.
CREATE OR REPLACE FUNCTION public.current_user_has_role(p_roles public.app_role[])
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT auth.uid() IS NOT NULL
     AND p_roles IS NOT NULL
     AND EXISTS (
       SELECT 1
       FROM unnest(p_roles) AS requested(role_code)
       WHERE public.current_user_has_role(requested.role_code)
     );
$$;

REVOKE ALL ON FUNCTION public.current_user_has_role(public.app_role[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.current_user_has_role(public.app_role[]) TO authenticated;
