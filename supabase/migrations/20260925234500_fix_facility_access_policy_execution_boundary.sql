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
        coalesce(qual, '') ~* '(^|[^_])has_facility_access[[:space:]]*\('
        OR coalesce(with_check, '') ~* '(^|[^_])has_facility_access[[:space:]]*\('
      )
      AND coalesce(qual, '') !~* 'current_user_has_facility_access'
      AND coalesce(with_check, '') !~* 'current_user_has_facility_access'
  LOOP
    -- These policies all evaluate the current authenticated session. Replace
    -- only the auth.uid()-bound two-argument helper calls with the one-argument
    -- session wrapper. Do not alter internal SECURITY DEFINER function bodies.
    v_qual := p.qual;
    v_check := p.with_check;

    -- The canonical healthcare-facility policy has a known safe target. Handle
    -- it explicitly because PostgreSQL may deparse auth.uid() subqueries with
    -- or without the generated "AS uid" alias.
    IF p.tablename = 'healthcare_facilities'
       AND p.policyname = 'healthcare_facilities_access' THEN
      v_qual := 'public.current_user_has_facility_access(id)';
      IF p.with_check IS NOT NULL THEN
        v_check := 'public.current_user_has_facility_access(id)';
      END IF;
    ELSIF p.tablename = 'facility_report_config'
       AND p.policyname = 'facility_report_config_access' THEN
      -- This policy's canonical expression is bound to facility_id. Use an
      -- explicit target because pg_get_expr may deparse the auth.uid() scalar
      -- subquery in a form not covered by the generic expression matcher.
      v_qual := 'public.current_user_has_facility_access(facility_id)';
    ELSIF p.tablename = 'report_generation_items'
       AND p.policyname = 'report_generation_items_insert' THEN
      -- Preserve the parent-run existence check and its facility scope. The
      -- nested auth.uid() expression is deparsed differently across versions.
      v_check := 'EXISTS (SELECT 1 FROM public.report_generation_runs r WHERE r.id = run_id AND public.current_user_has_facility_access(r.facility_id))';
    ELSIF p.tablename = 'report_submissions'
       AND p.policyname = 'report_submissions_access' THEN
      -- Preserve the facility_id scope; the original policy is a direct
      -- facility-membership check for the authenticated session.
      v_qual := 'public.current_user_has_facility_access(facility_id)';
    ELSE
      v_qual := regexp_replace(
        v_qual,
        'has_facility_access\(\s*\(*\s*(?:SELECT\s+auth\.uid\(\)\s*(?:AS\s+uid\s*)?|auth\.uid\(\))\)*\s*,\s*((?:"[A-Za-z_][A-Za-z0-9_$]*"|[A-Za-z_][A-Za-z0-9_$]*)(?:\s*\.\s*(?:"[A-Za-z_][A-Za-z0-9_$]*"|[A-Za-z_][A-Za-z0-9_$]*))*)\s*\)',
        'public.current_user_has_facility_access(\1)',
        'gi'
      );
    END IF;
    v_check := regexp_replace(
      v_check,
      'has_facility_access\(\s*\(*\s*(?:SELECT\s+auth\.uid\(\)\s*(?:AS\s+uid\s*)?|auth\.uid\(\))\)*\s*,\s*((?:"[A-Za-z_][A-Za-z0-9_$]*"|[A-Za-z_][A-Za-z0-9_$]*)(?:\s*\.\s*(?:"[A-Za-z_][A-Za-z0-9_$]*"|[A-Za-z_][A-Za-z0-9_$]*))*)\s*\)',
      'public.current_user_has_facility_access(\1)',
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
