-- Keep the low-level facility authorization helper internal-only.
-- Client-visible RLS policies must call the authenticated-session wrapper instead.
-- This preserves the existing SECURITY DEFINER execution boundary while fixing
-- direct policy evaluation failures for authenticated users, including admins.

DO $$
DECLARE
  p record;
  v_qual text;
  v_check text;
  v_has_qual boolean;
  v_has_check boolean;
BEGIN
  IF to_regprocedure('public.current_user_has_facility_access(uuid)') IS NULL THEN
    RAISE EXCEPTION 'Required current_user_has_facility_access(uuid) authorization wrapper is missing';
  END IF;

  -- Pin the wrapper before rewriting policies. Its body uses schema-qualified
  -- objects, so an empty search_path is safe and prevents shadow-object attacks.
  EXECUTE $cmd$ALTER FUNCTION public.current_user_has_facility_access(uuid) SET search_path = ''$cmd$;
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
    WHERE p.oid = to_regprocedure('public.current_user_has_facility_access(uuid)')
      AND p.prosecdef
      AND p.proconfig @> ARRAY['search_path=""']
  ) THEN
    RAISE EXCEPTION 'current_user_has_facility_access(uuid) must be SECURITY DEFINER with an empty pinned search_path';
  END IF;

  -- This known policy should not depend on PostgreSQL's pg_policies deparse
  -- form for the auth.uid() subquery (which can omit the synthetic AS uid).
  IF EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'healthcare_facilities'
      AND policyname = 'healthcare_facilities_access'
  ) THEN
    EXECUTE 'ALTER POLICY healthcare_facilities_access ON public.healthcare_facilities USING (public.current_user_has_facility_access(id))';
  END IF;

  FOR p IN
    SELECT schemaname, tablename, policyname, cmd, qual, with_check
    FROM pg_policies
    WHERE schemaname = 'public'
      AND (
        coalesce(qual, '') ~* '(^|[^_])has_facility_access[[:space:]]*\('
        OR coalesce(with_check, '') ~* '(^|[^_])has_facility_access[[:space:]]*\('
      )
      AND coalesce(qual, '') !~* 'current_user_has_facility_access'
      AND coalesce(with_check, '') !~* 'current_user_has_facility_access';
  LOOP
    -- These policies all evaluate the current authenticated session. Replace
    -- only the auth.uid()-bound two-argument helper calls with the one-argument
    -- session wrapper. Do not alter internal SECURITY DEFINER function bodies.
    v_qual := p.qual;
    v_check := p.with_check;

    v_qual := regexp_replace(
      v_qual,
      'has_facility_access[[:space:]]*\([[:space:]]*\([[:space:]]*SELECT[[:space:]]+auth\.uid\(\)[[:space:]]*(AS[[:space:]]+uid)?[[:space:]]*\)[[:space:]]*,[[:space:]]*([^,()]+)[[:space:]]*\)',
      'current_user_has_facility_access(\2)',
      'gi'
    );
    v_check := regexp_replace(
      v_check,
      'has_facility_access[[:space:]]*\([[:space:]]*\([[:space:]]*SELECT[[:space:]]+auth\.uid\(\)[[:space:]]*(AS[[:space:]]+uid)?[[:space:]]*\)[[:space:]]*,[[:space:]]*([^,()]+)[[:space:]]*\)',
      'current_user_has_facility_access(\2)',
      'gi'
    );

    v_has_qual := v_qual IS DISTINCT FROM p.qual;
    v_has_check := v_check IS DISTINCT FROM p.with_check;

    IF NOT (v_has_qual OR v_has_check) THEN
      RAISE EXCEPTION 'Unrecognized has_facility_access policy expression: %.%', p.tablename, p.policyname;
    END IF;

    IF p.cmd = 'INSERT' THEN
      EXECUTE format(
        'ALTER POLICY %I ON %I.%I WITH CHECK (%s)',
        p.policyname, p.schemaname, p.tablename, v_check
      );
    ELSIF p.cmd = 'DELETE' OR p.cmd = 'SELECT' THEN
      EXECUTE format(
        'ALTER POLICY %I ON %I.%I USING (%s)',
        p.policyname, p.schemaname, p.tablename, v_qual
      );
    ELSE
      EXECUTE format(
        'ALTER POLICY %I ON %I.%I USING (%s) WITH CHECK (%s)',
        p.policyname, p.schemaname, p.tablename, v_qual, v_check
      );
    END IF;
  END LOOP;
END;
$$;

-- Contract checks: the low-level helper remains internal-only, while the
-- session-scoped wrapper is callable by authenticated RLS evaluation.
REVOKE EXECUTE ON FUNCTION public.has_facility_access(uuid, uuid) FROM authenticated, anon, public;
GRANT EXECUTE ON FUNCTION public.current_user_has_facility_access(uuid) TO authenticated;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND (
        coalesce(qual, '') ~* '(^|[^_])has_facility_access[[:space:]]*\('
        OR coalesce(with_check, '') ~* '(^|[^_])has_facility_access[[:space:]]*\('
      )
      AND coalesce(qual, '') !~* 'current_user_has_facility_access'
      AND coalesce(with_check, '') !~* 'current_user_has_facility_access'
  ) THEN
    RAISE EXCEPTION 'Direct has_facility_access calls remain in authenticated RLS policies';
  END IF;
END;
$$;
