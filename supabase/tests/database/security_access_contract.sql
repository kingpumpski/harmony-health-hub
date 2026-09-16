begin;

select plan(5);

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

select * from finish();
rollback;
