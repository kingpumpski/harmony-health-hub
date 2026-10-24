begin;
select plan(40);
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
select has_column('public','department_queues','queued_at','legacy department queue timestamp exists before queue RPCs use it');
select has_index('public','department_queues','idx_department_queues_work','department queue work index exists after timestamp reconciliation');
select has_table('public','patient_audit','canonical patient audit table exists');
select ok(
  EXISTS (
    SELECT 1
    FROM pg_proc p
    WHERE p.oid = 'public.audit_patient_change()'::regprocedure
      AND p.prosecdef
      AND p.proconfig @> ARRAY['search_path=""']
  ),
  'patient audit trigger is security definer with an empty pinned search_path'
);
select has_column('public','medication_administrations','medication_name','legacy MAR medication name is reconciled');
select has_column('public','medication_administrations','scheduled_at','legacy MAR scheduling timestamp is reconciled');
select has_column('public','medication_administrations','status','legacy MAR status is reconciled');
select has_column('public','medication_administrations','updated_at','legacy MAR updated timestamp is reconciled');
select has_index('public','medication_administrations','idx_mar_patient_time','MAR patient scheduling index exists');
select ok(
  EXISTS (
    SELECT 1 FROM pg_constraint c
    WHERE c.conrelid = 'public.medication_administrations'::regclass
      AND c.conname = 'medication_administrations_status_check'
      AND position('not_given' in pg_get_constraintdef(c.oid)) > 0
  ),
  'MAR status constraint supports not_given outcomes'
);
select ok(
  NOT EXISTS (
    SELECT 1
    FROM pg_policies p
    WHERE p.schemaname = 'public'
      AND (COALESCE(p.qual, '') || ' ' || COALESCE(p.with_check, ''))
          ~* '(^|[^a-zA-Z0-9_])has_facility_access[[:space:]]*\('
  ),
  'public RLS policies use the session-scoped facility authorization wrapper'
);
select ok(
  to_regclass('public.patient_audit_log') IS NOT NULL
  AND EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgname = 't_patient_audit_changes'
      AND NOT tgisinternal
  ),
  'patient audit log table and trigger exist for the Patient Audit screen'
);
select ok(
  EXISTS (
    SELECT 1 FROM pg_proc p
    WHERE p.oid = 'public.audit_patient_changes()'::regprocedure
      AND p.prosecdef
      AND p.proconfig @> ARRAY['search_path=""']
  ),
  'patient audit log trigger is security definer with an empty pinned search_path'
);
select has_column('public','theatre_cases','theatre_name','legacy theatre name is reconciled');
select has_column('public','theatre_cases','anesthetist_id','application-facing anesthetist field is reconciled');
select has_column('public','theatre_cases','scheduled_start','application-facing theatre schedule is reconciled');
select has_column('public','theatre_cases','urgency','theatre urgency field is reconciled');
select has_column('public','theatre_cases','encounter_id','theatre encounter link is reconciled');
select ok(
  EXISTS (
    SELECT 1 FROM pg_constraint c
    WHERE c.conrelid = 'public.theatre_cases'::regclass
      AND c.conname = 'theatre_cases_status_check'
      AND position('requested' in pg_get_constraintdef(c.oid)) > 0
      AND position('scheduled' in pg_get_constraintdef(c.oid)) > 0
  ),
  'theatre status constraint supports legacy and current lifecycle states'
);
select has_index('public','theatre_cases','idx_theatre_schedule','theatre schedule index exists');
select * from finish();
rollback;
