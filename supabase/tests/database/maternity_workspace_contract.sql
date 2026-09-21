begin;
select plan(2);
select ok(
 (select pg_get_functiondef(p.oid) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='get_maternity_workspace'
  and pg_get_function_identity_arguments(p.oid)='_limit integer, _episode_id uuid')
 ilike '%JOIN public.patients p ON p.id = me.patient_id%'
 and (select pg_get_functiondef(p.oid) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='get_maternity_workspace'
  and pg_get_function_identity_arguments(p.oid)='_limit integer, _episode_id uuid')
 ilike '%Maternity episode not found%',
 'maternity workspace validates episode-to-patient linkage'
);
select ok(
 (select pg_get_functiondef(p.oid) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='get_maternity_workspace'
  and pg_get_function_identity_arguments(p.oid)='_limit integer, _episode_id uuid')
 ilike '%REVOKE ALL ON FUNCTION public.get_maternity_workspace(INTEGER,UUID) FROM PUBLIC, anon%'
 or (select has_function_privilege('anon', 'public.get_maternity_workspace(integer,uuid)', 'EXECUTE')) = false,
 'maternity workspace is not executable by anon'
);
select * from finish();
rollback;