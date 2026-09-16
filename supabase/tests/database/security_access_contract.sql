begin;

select plan(7);

select ok(
  (select relrowsecurity from pg_class where oid = 'public.user_roles'::regclass),
  'user_roles has RLS enabled'
);

select ok(
  exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'user_roles'
      and policyname = 'user_roles_select_own'
      and qual is not null
      and qual ilike '%auth.uid%'
  ),
  'user_roles read policy is scoped to the current user'
);

select ok(
  exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'facility_memberships'
      and policyname = 'memberships_read'
      and qual is not null
      and qual ilike '%auth.uid%'
  ),
  'facility membership reads are scoped to the current user or administrator'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.notify_due_medications()',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'public.lock_overdue_medication_slots()',
    'EXECUTE'
  ),
  'internal medication maintenance functions are not callable by authenticated clients'
);

select ok(
  exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'patients'
      and policyname = 'authorized users read patients'
      and qual is not null
      and qual not in ('true', '(true)')
  ),
  'patient reads are governed by an authorization predicate'
);

select ok(
  (
    select count(*)
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in (
        'grant_service_order_override',
        'release_service_order',
        'cancel_service_order',
        'mark_service_order_in_progress',
        'complete_service_order'
      )
      and p.prosecdef
      and not has_function_privilege('anon', p.oid, 'EXECUTE')
      and has_function_privilege('authenticated', p.oid, 'EXECUTE')
  ) = 5,
  'service-order lifecycle RPCs are security-definer and authenticated-only'
);

select ok(
  has_function_privilege('authenticated', 'public.release_service_order(uuid,text)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.release_service_order(uuid,text)', 'EXECUTE')
  and (
    select pg_get_functiondef(p.oid)
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'release_service_order'
      and pg_get_function_identity_arguments(p.oid) = 'uuid, _reason text'
  ) ilike '%has_role(auth.uid(),''front_desk'')%',
  'payment release is authenticated-only and permits the front-desk payment workflow'
);

select * from finish();
rollback;
