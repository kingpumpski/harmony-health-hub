begin;
select plan(2);
select ok(
  (select pg_get_functiondef(p.oid) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='search_patient_directory'
   and pg_get_function_identity_arguments(p.oid)='_query text, _limit integer')
   ilike '%CASE WHEN can_sensitive THEN p.ghana_card_number ELSE NULL END%'
   and (select pg_get_functiondef(p.oid) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='search_patient_directory'
   and pg_get_function_identity_arguments(p.oid)='_query text, _limit integer')
   ilike '%Authentication required%',
  'patient directory masks identity/insurance identifiers for non-sensitive roles'
);
select ok(
  (select pg_get_functiondef(p.oid) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='create_workflow_notification'
   and pg_get_function_identity_arguments(p.oid)='_recipient_role text, _recipient_user_id uuid, _title text, _message text, _severity text, _category text, _link text, _related_patient_id uuid, _related_entity_id uuid, _metadata jsonb')
   ilike '%Non-administrators may only target their own notification inbox%'
   and (select pg_get_functiondef(p.oid) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='create_workflow_notification'
   and pg_get_function_identity_arguments(p.oid)='_recipient_role text, _recipient_user_id uuid, _title text, _message text, _severity text, _category text, _link text, _related_patient_id uuid, _related_entity_id uuid, _metadata jsonb')
   ilike '%Related patient does not exist%',
  'workflow notification creation prevents arbitrary user targeting and invalid patient references'
);
select * from finish();
rollback;