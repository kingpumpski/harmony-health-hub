-- Compatibility overloads for legacy enterprise HIMS policies.
-- Existing single-role helpers remain the authorization source of truth.
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
       SELECT 1 FROM unnest(p_roles) AS requested(role_code)
       WHERE public.has_role(p_user_id, requested.role_code)
     );
$$;
REVOKE ALL ON FUNCTION public.has_role(uuid, public.app_role[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.has_role(uuid, public.app_role[]) TO authenticated;

-- Later policy normalization rewrites legacy array checks to this overload.
-- Dynamic invocation intentionally defers resolution of the established
-- single-role helper until this function is called, because that helper is
-- introduced by a later migration in the historical chain.
CREATE OR REPLACE FUNCTION public.current_user_has_role(p_roles public.app_role[])
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  requested_role public.app_role;
  role_match boolean;
BEGIN
  IF auth.uid() IS NULL OR p_roles IS NULL THEN
    RETURN false;
  END IF;

  FOREACH requested_role IN ARRAY p_roles LOOP
    EXECUTE 'SELECT public.current_user_has_role($1)'
      INTO role_match USING requested_role;
    IF COALESCE(role_match, false) THEN
      RETURN true;
    END IF;
  END LOOP;
  RETURN false;
END;
$$;
REVOKE ALL ON FUNCTION public.current_user_has_role(public.app_role[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.current_user_has_role(public.app_role[]) TO authenticated;
