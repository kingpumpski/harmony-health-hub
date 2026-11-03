BEGIN;

SELECT plan(26);

SELECT has_column('public','bulk_import_jobs','entity_type','bulk import entity type is present');
SELECT has_column('public','bulk_import_jobs','source_format','bulk import source format is present');
SELECT has_column('public','bulk_import_jobs','file_name','bulk import file name is present');
SELECT has_column('public','bulk_import_jobs','successful_rows','bulk import successful row count is present');
SELECT has_column('public','bulk_import_jobs','completed_at','bulk import completion timestamp is present');
SELECT col_not_null('public','bulk_import_jobs','entity_type','bulk import entity type is required');
SELECT col_not_null('public','bulk_import_jobs','source_format','bulk import source format is required');

SELECT ok(
  EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.bulk_import_jobs'::regclass AND conname='bulk_import_jobs_entity_type_check'),
  'bulk import entity type values are constrained'
);
SELECT ok(
  EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.bulk_import_jobs'::regclass AND conname='bulk_import_jobs_source_format_check'),
  'bulk import source format values are constrained'
);

SELECT ok(
  EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid='public.ensure_updated_at()'::regprocedure AND p.proconfig @> ARRAY['search_path=pg_catalog']),
  'ensure_updated_at has a pinned pg_catalog search path'
);
SELECT ok(NOT has_function_privilege('anon','public.ensure_updated_at()','EXECUTE'),'anon cannot call the trigger helper directly');
SELECT ok(NOT has_function_privilege('authenticated','public.ensure_updated_at()','EXECUTE'),'authenticated cannot call the trigger helper directly');
SELECT ok(NOT has_function_privilege('service_role','public.ensure_updated_at()','EXECUTE'),'service_role cannot call the trigger helper directly');
SELECT ok(
  EXISTS (SELECT 1 FROM pg_trigger WHERE NOT tgisinternal AND tgfoid='public.ensure_updated_at()'::regprocedure),
  'updated_at triggers remain attached after direct execute is revoked'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_policy p
    WHERE p.polrelid='public.lab_test_groups'::regclass
      AND p.polname='lab_test_groups_deny_direct_api'
      AND NOT p.polpermissive
      AND pg_get_expr(p.polqual,p.polrelid)='false'
      AND pg_get_expr(p.polwithcheck,p.polrelid)='false'
  ),
  'laboratory panel table has an explicit restrictive deny policy'
);
SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_policy p
    WHERE p.polrelid='public.lab_test_group_items'::regclass
      AND p.polname='lab_test_group_items_deny_direct_api'
      AND NOT p.polpermissive
      AND pg_get_expr(p.polqual,p.polrelid)='false'
      AND pg_get_expr(p.polwithcheck,p.polrelid)='false'
  ),
  'laboratory panel membership table has an explicit restrictive deny policy'
);
SELECT ok(NOT has_table_privilege('anon','public.lab_test_groups','SELECT'),'anon has no direct SELECT grant on laboratory panels');
SELECT ok(NOT has_table_privilege('authenticated','public.lab_test_groups','SELECT'),'authenticated has no direct SELECT grant on laboratory panels');
SELECT ok(NOT has_table_privilege('anon','public.lab_test_group_items','SELECT'),'anon has no direct SELECT grant on laboratory panel membership');
SELECT ok(NOT has_table_privilege('authenticated','public.lab_test_group_items','SELECT'),'authenticated has no direct SELECT grant on laboratory panel membership');

SELECT ok(
  NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.billing_overrides'::regclass AND conname='billing_overrides_service_order_fk'),
  'duplicate billing override service-order foreign key is removed'
);
SELECT ok(
  NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.department_queues'::regclass AND conname='department_queues_service_order_fk'),
  'duplicate department queue service-order foreign key is removed'
);
SELECT ok(
  to_regclass('public.lab_result_attachments_result_idx') IS NULL,
  'duplicate lab result attachment index is removed'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.prosecdef
      AND has_function_privilege('anon',p.oid,'EXECUTE')
  ),
  'no public SECURITY DEFINER function is executable by anon'
);
SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.prosecdef
      AND NOT EXISTS (
        SELECT 1 FROM unnest(coalesce(p.proconfig,ARRAY[]::text[])) setting
        WHERE setting LIKE 'search_path=%'
      )
  ),
  'every public SECURITY DEFINER function has a pinned search_path'
);
SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.prosecdef
      AND has_function_privilege('authenticated',p.oid,'EXECUTE')
      AND p.prosrc NOT ILIKE '%auth.uid%'
      AND p.prosrc NOT ILIKE '%auth.jwt%'
      AND p.prosrc NOT ILIKE '%has_role%'
      AND p.prosrc NOT ILIKE '%current_user_has_role%'
      AND p.prosrc NOT ILIKE '%current_user_is_%'
      AND p.prosrc NOT ILIKE '%current_user_facility_id%'
      AND p.prosrc NOT ILIKE '%current_user_can_edit%'
      AND p.prosrc NOT ILIKE '%has_facility_access%'
      AND p.prosrc NOT ILIKE '%assert_patient_facility%'
      AND p.prosrc NOT ILIKE '%public.create_lab_test_catalogue_item_with_parameters%'
      AND p.prosrc NOT ILIKE '%public.create_ward_unit%'
  ),
  'authenticated SECURITY DEFINER RPCs contain an auth/facility guard or delegate to a guarded RPC'
);

SELECT * FROM finish();
ROLLBACK;
