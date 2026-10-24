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
  FOR p IN
    SELECT schemaname, tablename, policyname, cmd, qual, with_check
    FROM pg_policies
    WHERE schemaname = 'public'
      AND (
        coalesce(qual, '') ~* '(^|[^_])has_facility_access[[:space:]]*[(]'
        OR coalesce(with_check, '') ~* '(^|[^_])has_facility_access[[:space:]]*[(]'
      )
  LOOP
    -- These policies all evaluate the current authenticated session. Replace
    -- only the auth.uid()-bound two-argument helper calls with the one-argument
    -- session wrapper. Do not alter internal SECURITY DEFINER function bodies.
    v_qual := p.qual;
    v_check := p.with_check;

    v_qual := regexp_replace(
      v_qual,
      'has_facility_access[[:space:]]*[(][^,]*auth[.]uid[(][)][^,]*,[[:space:]]*([A-Za-z_][A-Za-z0-9_.]*)[[:space:]]*[)]',
      'current_user_has_facility_access(\1)',
      'gi'
    );
    v_check := regexp_replace(
      v_check,
      'has_facility_access[[:space:]]*[(][^,]*auth[.]uid[(][)][^,]*,[[:space:]]*([A-Za-z_][A-Za-z0-9_.]*)[[:space:]]*[)]',
      'current_user_has_facility_access(\1)',
      'gi'
    );

    v_has_qual := v_qual IS DISTINCT FROM p.qual;
    v_has_check := v_check IS DISTINCT FROM p.with_check;

    IF NOT (v_has_qual OR v_has_check) THEN
      RAISE EXCEPTION 'Unrecognized has_facility_access policy expression: %.%', p.tablename, p.policyname;
    END IF;

    IF p.cmd = 'INSERT' THEN
      IF v_has_check THEN
        EXECUTE format(
          'ALTER POLICY %I ON %I.%I WITH CHECK (%s)',
          p.policyname, p.schemaname, p.tablename, v_check
        );
      END IF;
    ELSIF p.cmd = 'DELETE' OR p.cmd = 'SELECT' THEN
      IF v_has_qual THEN
        EXECUTE format(
          'ALTER POLICY %I ON %I.%I USING (%s)',
          p.policyname, p.schemaname, p.tablename, v_qual
        );
      END IF;
    ELSE
      IF v_has_qual AND v_has_check THEN
        EXECUTE format(
          'ALTER POLICY %I ON %I.%I USING (%s) WITH CHECK (%s)',
          p.policyname, p.schemaname, p.tablename, v_qual, v_check
        );
      ELSIF v_has_qual THEN
        EXECUTE format(
          'ALTER POLICY %I ON %I.%I USING (%s)',
          p.policyname, p.schemaname, p.tablename, v_qual
        );
      ELSIF v_has_check THEN
        EXECUTE format(
          'ALTER POLICY %I ON %I.%I WITH CHECK (%s)',
          p.policyname, p.schemaname, p.tablename, v_check
        );
      END IF;
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
        coalesce(qual, '') ~* '(^|[^_])has_facility_access[[:space:]]*[(]'
        OR coalesce(with_check, '') ~* '(^|[^_])has_facility_access[[:space:]]*[(]'
      )
  ) THEN
    RAISE EXCEPTION 'Direct has_facility_access calls remain in authenticated RLS policies';
  END IF;
END;
$$;
