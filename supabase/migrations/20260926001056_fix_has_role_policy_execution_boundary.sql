-- Keep the low-level role authorization helper internal-only.
-- Public RLS policies must use the authenticated-session wrapper instead.
-- This mirrors the facility-access execution boundary and prevents
-- authenticated clients from failing with "permission denied for function has_role".

DO $$
DECLARE p record; v_qual text; v_check text;
BEGIN
  FOR p IN
    SELECT schemaname,tablename,policyname,cmd,qual,with_check
    FROM pg_policies
    WHERE schemaname='public'
      AND (coalesce(qual,'') LIKE '%has_role(%' OR coalesce(with_check,'') LIKE '%has_role(%')
      AND coalesce(qual,'') NOT LIKE '%current_user_has_role(%'
      AND coalesce(with_check,'') NOT LIKE '%current_user_has_role(%'
  LOOP
    v_qual := p.qual;
    v_check := p.with_check;
    v_qual := replace(v_qual, 'has_role(( SELECT auth.uid() AS uid), ', 'current_user_has_role(');
    v_check := replace(v_check, 'has_role(( SELECT auth.uid() AS uid), ', 'current_user_has_role(');
    v_qual := replace(v_qual, 'has_role((SELECT auth.uid() AS uid), ', 'current_user_has_role(');
    v_check := replace(v_check, 'has_role((SELECT auth.uid() AS uid), ', 'current_user_has_role(');
    v_qual := replace(v_qual, 'has_role(auth.uid(), ', 'current_user_has_role(');
    v_check := replace(v_check, 'has_role(auth.uid(), ', 'current_user_has_role(');
    IF v_qual IS NOT DISTINCT FROM p.qual AND v_check IS NOT DISTINCT FROM p.with_check THEN
      RAISE EXCEPTION 'Could not rewrite policy %.%',p.tablename,p.policyname;
    END IF;
    IF p.cmd='INSERT' THEN
      EXECUTE format('ALTER POLICY %I ON %I.%I WITH CHECK (%s)',p.policyname,p.schemaname,p.tablename,v_check);
    ELSIF p.cmd IN ('SELECT','DELETE') THEN
      EXECUTE format('ALTER POLICY %I ON %I.%I USING (%s)',p.policyname,p.schemaname,p.tablename,v_qual);
    ELSIF v_qual IS NULL THEN
      EXECUTE format('ALTER POLICY %I ON %I.%I WITH CHECK (%s)',p.policyname,p.schemaname,p.tablename,v_check);
    ELSIF v_check IS NULL THEN
      EXECUTE format('ALTER POLICY %I ON %I.%I USING (%s)',p.policyname,p.schemaname,p.tablename,v_qual);
    ELSE
      EXECUTE format('ALTER POLICY %I ON %I.%I USING (%s) WITH CHECK (%s)',p.policyname,p.schemaname,p.tablename,v_qual,v_check);
    END IF;
  END LOOP;
END $$;

REVOKE EXECUTE ON FUNCTION public.has_role(uuid, public.app_role) FROM PUBLIC, authenticated, anon;
GRANT EXECUTE ON FUNCTION public.current_user_has_role(public.app_role) TO authenticated;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public'
      AND (coalesce(qual,'') LIKE '%has_role(%' OR coalesce(with_check,'') LIKE '%has_role(%')
      AND coalesce(qual,'') NOT LIKE '%current_user_has_role(%'
      AND coalesce(with_check,'') NOT LIKE '%current_user_has_role(%'
  ) THEN RAISE EXCEPTION 'Direct has_role calls remain in public RLS policies'; END IF;
END $$;
