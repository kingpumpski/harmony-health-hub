-- Security contract: every SECURITY DEFINER function exposed to authenticated must authenticate/authorize the caller,
-- and no SECURITY DEFINER function in public may be executable by anon/public.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.prosecdef
      AND has_function_privilege('authenticated', p.oid, 'EXECUTE')
      AND NOT (
        pg_get_functiondef(p.oid) ~* 'auth\\.uid\\(\\)|has_role\\(|is_clinical_staff\\(|has_facility_access\\('
        OR (
          p.proname = 'create_lab_test_catalogue_item_with_sample_quantity'
          AND pg_get_functiondef(p.oid) ILIKE '%create_lab_test_catalogue_item_with_parameters%'
        )
        OR (
          p.proname = 'create_ward_unit'
          AND pg_get_function_identity_arguments(p.oid) = '_name text, _code text, _specialty text, _gender_policy text'
          AND pg_get_functiondef(p.oid) ILIKE '%current_user_facility_id%'
          AND pg_get_functiondef(p.oid) ILIKE '%create_ward_unit%'
        )
      )
  ) THEN RAISE EXCEPTION 'SECURITY DEFINER function exposed to authenticated without an explicit auth/authorization guard'; END IF;
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.prosecdef
      AND (has_function_privilege('anon', p.oid, 'EXECUTE') OR has_function_privilege('public', p.oid, 'EXECUTE'))
  ) THEN RAISE EXCEPTION 'SECURITY DEFINER function in public schema is exposed to anon/public'; END IF;

  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.prosecdef
      AND (
        p.proconfig IS NULL
        OR NOT (
          p.proconfig @> ARRAY['search_path=""']::text[]
          OR p.proconfig @> ARRAY['search_path=pg_catalog, public']::text[]
          OR p.proconfig @> ARRAY['search_path="pg_catalog, public"']::text[]
        )
      )
  ) THEN RAISE EXCEPTION 'SECURITY DEFINER function has no approved pinned search_path'; END IF;

  IF has_schema_privilege('authenticated','public','CREATE')
     OR has_schema_privilege('anon','public','CREATE') THEN
    RAISE EXCEPTION 'Data API roles must not be able to create objects in public schema';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public'
      AND p.proname='create_lab_test_catalogue_item_with_parameters'
      AND p.prosecdef
      AND has_function_privilege('authenticated',p.oid,'EXECUTE')
      AND pg_get_functiondef(p.oid) ILIKE '%auth.uid()%'
      AND pg_get_functiondef(p.oid) ILIKE '%current_user_has_catalogue_create_permission%'
  ) THEN RAISE EXCEPTION 'Laboratory sample-quantity wrapper target must enforce authenticated catalogue permissions'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public'
      AND p.proname='create_ward_unit'
      AND pg_get_function_identity_arguments(p.oid)='_name text, _code text, _specialty text, _gender_policy text, _facility_id uuid'
      AND p.prosecdef
      AND has_function_privilege('authenticated',p.oid,'EXECUTE')
      AND pg_get_functiondef(p.oid) ILIKE '%auth.uid()%'
      AND pg_get_functiondef(p.oid) ILIKE '%has_role%'
      AND pg_get_functiondef(p.oid) ILIKE '%has_facility_access%'
  ) THEN RAISE EXCEPTION 'Ward creation delegate must enforce authenticated administrator and facility authorization'; END IF;
END $$;
SELECT 'security_definer_auth_contract' AS contract, 'pass' AS status;