BEGIN;

SELECT plan(21);

SELECT ok(
  (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.lab_test_groups'::regclass),
  'laboratory panel definitions must retain RLS'
);
SELECT ok(
  (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.lab_test_group_items'::regclass),
  'laboratory panel membership must retain RLS'
);

SELECT ok(NOT has_table_privilege('anon', 'public.lab_test_groups', 'SELECT'), 'anon cannot select panel definitions');
SELECT ok(NOT has_table_privilege('anon', 'public.lab_test_groups', 'INSERT'), 'anon cannot insert panel definitions');
SELECT ok(NOT has_table_privilege('anon', 'public.lab_test_groups', 'UPDATE'), 'anon cannot update panel definitions');
SELECT ok(NOT has_table_privilege('anon', 'public.lab_test_groups', 'DELETE'), 'anon cannot delete panel definitions');
SELECT ok(NOT has_table_privilege('authenticated', 'public.lab_test_groups', 'SELECT'), 'authenticated cannot select panel definitions directly');
SELECT ok(NOT has_table_privilege('authenticated', 'public.lab_test_groups', 'INSERT'), 'authenticated cannot insert panel definitions directly');
SELECT ok(NOT has_table_privilege('authenticated', 'public.lab_test_groups', 'UPDATE'), 'authenticated cannot update panel definitions directly');
SELECT ok(NOT has_table_privilege('authenticated', 'public.lab_test_groups', 'DELETE'), 'authenticated cannot delete panel definitions directly');

SELECT ok(NOT has_table_privilege('anon', 'public.lab_test_group_items', 'SELECT'), 'anon cannot select panel membership');
SELECT ok(NOT has_table_privilege('anon', 'public.lab_test_group_items', 'INSERT'), 'anon cannot insert panel membership');
SELECT ok(NOT has_table_privilege('anon', 'public.lab_test_group_items', 'UPDATE'), 'anon cannot update panel membership');
SELECT ok(NOT has_table_privilege('anon', 'public.lab_test_group_items', 'DELETE'), 'anon cannot delete panel membership');
SELECT ok(NOT has_table_privilege('authenticated', 'public.lab_test_group_items', 'SELECT'), 'authenticated cannot select panel membership directly');
SELECT ok(NOT has_table_privilege('authenticated', 'public.lab_test_group_items', 'INSERT'), 'authenticated cannot insert panel membership directly');
SELECT ok(NOT has_table_privilege('authenticated', 'public.lab_test_group_items', 'UPDATE'), 'authenticated cannot update panel membership directly');
SELECT ok(NOT has_table_privilege('authenticated', 'public.lab_test_group_items', 'DELETE'), 'authenticated cannot delete panel membership directly');

SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM pg_policy
    WHERE polrelid IN ('public.lab_test_groups'::regclass, 'public.lab_test_group_items'::regclass)
  ),
  'panel tables intentionally have no direct client policies; access is RPC-only'
);
SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'ensure_updated_at'
      AND coalesce(p.proconfig, ARRAY[]::text[]) @> ARRAY['search_path=""']::text[]
  ),
  'ensure_updated_at trigger function must use a pinned empty search_path'
);

SELECT * FROM finish();
ROLLBACK;
