-- Security contract: every SECURITY DEFINER function exposed to authenticated must authenticate/authorize the caller,
-- and no SECURITY DEFINER function in public may be executable by anon/public.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.prosecdef
      AND has_function_privilege('authenticated', p.oid, 'EXECUTE')
      AND NOT (pg_get_functiondef(p.oid) ~* 'auth\\.uid\\(\\)|has_role\\(|is_clinical_staff\\(|has_facility_access\\(')
  ) THEN RAISE EXCEPTION 'SECURITY DEFINER function exposed to authenticated without an explicit auth/authorization guard'; END IF;
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.prosecdef
      AND (has_function_privilege('anon', p.oid, 'EXECUTE') OR has_function_privilege('public', p.oid, 'EXECUTE'))
  ) THEN RAISE EXCEPTION 'SECURITY DEFINER function in public schema is exposed to anon/public'; END IF;
END $$;
SELECT 'security_definer_auth_contract' AS contract, 'pass' AS status;