begin;
select plan(20);
select has_table('public','lab_test_groups','laboratory panels table exists');
select has_table('public','lab_test_group_items','panel membership table exists');
select has_table('public','lab_result_attachments','attachment metadata table exists');
select has_column('public','lab_result_attachments','file_size_bytes','legacy attachment size metadata exists');
select has_index('public','lab_result_attachments','lab_result_attachments_id_legacy_uidx','legacy attachment identifiers are unique');
select has_column('public','lab_orders','group_id','lab_orders.group_id exists');
select has_column('public','lab_orders','parent_order_id','lab_orders.parent_order_id exists');
select has_column('public','lab_test_catalogue','sample_quantity','catalogue sample_quantity exists');
select has_index('public','lab_test_groups','lab_test_groups_facility_code_uidx','facility/code uniqueness exists');
select has_index('public','lab_orders','lab_orders_panel_child_test_uidx','panel child idempotency index exists');
select ok(exists(select 1 from pg_index i join pg_class t on t.oid=i.indrelid join pg_class ix on ix.oid=i.indexrelid join pg_attribute a on a.attrelid=t.oid and a.attname='storage_path' where t.oid='public.lab_result_attachments'::regclass and i.indisunique and a.attnum=any(i.indkey)),'attachment storage paths are unique');
select ok((select p.prorettype='jsonb'::regtype from pg_proc p where p.oid=to_regprocedure('public.get_laboratory_test_groups(boolean)')),'panel RPC return type is jsonb');
select ok((select p.prorettype='jsonb'::regtype from pg_proc p where p.oid=to_regprocedure('public.get_lab_result_attachments(uuid[])')),'attachment RPC return type is jsonb');
select ok((select p.prosecdef and p.proconfig @> array['search_path=""'] from pg_proc p where p.oid=to_regprocedure('public.get_lab_result_attachments(uuid[])')),'attachment RPC pins empty search_path');
select ok(not has_function_privilege('anon','public.get_lab_result_attachments(uuid[])','EXECUTE'),'anon cannot execute attachment RPC');
select ok(not exists(select 1 from pg_proc p cross join lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where p.oid=to_regprocedure('public.get_lab_result_attachments(uuid[])') and a.grantee=0 and a.privilege_type='EXECUTE'),'PUBLIC cannot execute attachment RPC');
select ok(has_function_privilege('authenticated','public.get_lab_result_attachments(uuid[])','EXECUTE'),'authenticated can invoke guarded attachment RPC');
select ok((select relrowsecurity from pg_class where oid='public.lab_result_attachments'::regclass),'attachment metadata has RLS enabled');
select ok(exists(select 1 from pg_policies where schemaname='public' and tablename='lab_result_attachments' and qual ilike '%current_user_facility_id%'),'attachment policies retain facility scope');
select ok(exists(select 1 from pg_policies where schemaname='public' and tablename='lab_result_attachments' and with_check ilike '%service_orders%'),'attachment writes require service-order lineage');
select * from finish();
rollback;


DO $$
BEGIN
  ASSERT NOT has_function_privilege('authenticated', 'public.has_facility_access(uuid,uuid)', 'EXECUTE'),
    'authenticated clients must not execute the low-level arbitrary-user facility helper';
  ASSERT NOT has_function_privilege('anon', 'public.has_facility_access(uuid,uuid)', 'EXECUTE'),
    'anonymous clients must not execute the low-level arbitrary-user facility helper';
  ASSERT has_function_privilege('authenticated', 'public.current_user_has_facility_access(uuid)', 'EXECUTE'),
    'authenticated RLS evaluation must retain the session-scoped facility helper';
  ASSERT EXISTS (
    SELECT 1
    FROM pg_proc p
    WHERE p.oid='public.current_user_has_facility_access(uuid)'::regprocedure
      AND p.prosecdef
      AND p.proconfig @> ARRAY['search_path=""']::text[]
  ), 'session facility helper must be SECURITY DEFINER with an empty pinned search path';
  ASSERT NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname='public'
      AND (
        coalesce(qual,'') ~* '(^|[^_])has_facility_access[[:space:]]*\('
        OR coalesce(with_check,'') ~* '(^|[^_])has_facility_access[[:space:]]*\('
      )
  ), 'public RLS policies must not call the low-level facility helper directly';
END $$;


DO $$
BEGIN
  ASSERT NOT has_function_privilege('authenticated', 'public.has_role(uuid,public.app_role)', 'EXECUTE'),
    'authenticated clients must not execute the low-level arbitrary-user role helper';
  ASSERT NOT has_function_privilege('anon', 'public.has_role(uuid,public.app_role)', 'EXECUTE'),
    'anonymous clients must not execute the low-level arbitrary-user role helper';
  ASSERT has_function_privilege('authenticated', 'public.current_user_has_role(public.app_role)', 'EXECUTE'),
    'authenticated RLS evaluation must retain the session-scoped role helper';
  ASSERT EXISTS (
    SELECT 1 FROM pg_proc p
    WHERE p.oid='public.current_user_has_role(public.app_role)'::regprocedure
      AND p.prosecdef
      AND p.proconfig IS NOT NULL
      AND EXISTS (SELECT 1 FROM unnest(p.proconfig) setting WHERE setting LIKE 'search_path=%')
  ), 'session role helper must be SECURITY DEFINER with a pinned search_path';
  ASSERT NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public'
      AND (
        coalesce(qual,'') ~* '(^|[^_])has_role[[:space:]]*[(]'
        OR coalesce(with_check,'') ~* '(^|[^_])has_role[[:space:]]*[(]'
      )
  ), 'public RLS policies must not call the low-level role helper directly';
END $$;
