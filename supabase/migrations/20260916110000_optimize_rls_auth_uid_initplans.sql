-- Preserve RLS semantics while preventing per-row re-evaluation of auth.uid().
-- Existing scalar-subquery wrappers are normalized rather than nested.
DO $$
DECLARE
  p record;
  v_qual text;
  v_check text;
  v_sql text;
BEGIN
  FOR p IN
    SELECT schemaname, tablename, policyname, qual, with_check
    FROM pg_policies
    WHERE schemaname = 'public'
      AND (
        coalesce(qual, '') LIKE '%auth.uid()%'
        OR coalesce(with_check, '') LIKE '%auth.uid()%'
      )
  LOOP
    v_qual := p.qual;
    v_check := p.with_check;

    IF v_qual IS NOT NULL THEN
      v_qual := replace(v_qual, '(select auth.uid())', '__SUPABASE_UID_MARKER__');
      v_qual := replace(v_qual, 'auth.uid()', '(select auth.uid())');
      v_qual := replace(v_qual, '__SUPABASE_UID_MARKER__', '(select auth.uid())');
      WHILE position('( SELECT ( SELECT auth.uid() AS uid) AS uid)' in v_qual) > 0 LOOP
        v_qual := replace(v_qual, '( SELECT ( SELECT auth.uid() AS uid) AS uid)', '( SELECT auth.uid() AS uid)');
      END LOOP;
    END IF;

    IF v_check IS NOT NULL THEN
      v_check := replace(v_check, '(select auth.uid())', '__SUPABASE_UID_MARKER__');
      v_check := replace(v_check, 'auth.uid()', '(select auth.uid())');
      v_check := replace(v_check, '__SUPABASE_UID_MARKER__', '(select auth.uid())');
      WHILE position('( SELECT ( SELECT auth.uid() AS uid) AS uid)' in v_check) > 0 LOOP
        v_check := replace(v_check, '( SELECT ( SELECT auth.uid() AS uid) AS uid)', '( SELECT auth.uid() AS uid)');
      END LOOP;
    END IF;

    IF v_qual IS NOT NULL AND v_check IS NOT NULL THEN
      v_sql := format('ALTER POLICY %I ON %I.%I USING (%s) WITH CHECK (%s)', p.policyname, p.schemaname, p.tablename, v_qual, v_check);
    ELSIF v_qual IS NOT NULL THEN
      v_sql := format('ALTER POLICY %I ON %I.%I USING (%s)', p.policyname, p.schemaname, p.tablename, v_qual);
    ELSE
      v_sql := format('ALTER POLICY %I ON %I.%I WITH CHECK (%s)', p.policyname, p.schemaname, p.tablename, v_check);
    END IF;

    EXECUTE v_sql;
  END LOOP;
END $$;