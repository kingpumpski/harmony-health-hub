create table if not exists public.hms_test_runtime_audit (
  id uuid primary key default gen_random_uuid(),
  changed_by uuid not null references auth.users(id),
  previous_enabled boolean not null,
  new_enabled boolean not null,
  reason text not null,
  changed_at timestamptz not null default now()
);

alter table public.hms_test_runtime_audit enable row level security;
revoke all on public.hms_test_runtime_audit from public, anon, authenticated;

create or replace function public.get_hms_test_runtime_status()
returns table(enabled boolean, updated_at timestamptz, changed_by uuid)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.user_roles
    where user_id = auth.uid()
      and role = 'system_superuser'
  ) then
    raise exception 'Only system super administrators can view environment mode.';
  end if;

  return query
  select r.enabled, r.updated_at,
    (
      select a.changed_by
      from public.hms_test_runtime_audit a
      where a.new_enabled = r.enabled
      order by a.changed_at desc
      limit 1
    )
  from public.hms_test_runtime r
  where r.id = true;
end;
$$;

create or replace function public.set_hms_test_runtime(_enabled boolean, _reason text)
returns table(enabled boolean, updated_at timestamptz)
language plpgsql
security definer
set search_path = ''
as $$
declare
  previous_enabled boolean;
  next_updated_at timestamptz;
  actor uuid := auth.uid();
  normalized_reason text := nullif(btrim(coalesce(_reason, '')), '');
begin
  if actor is null then
    raise exception 'Authentication required.';
  end if;

  if not exists (
    select 1 from public.user_roles
    where user_id = actor
      and role = 'system_superuser'
  ) then
    raise exception 'Only system super administrators can change environment mode.';
  end if;

  if normalized_reason is null then
    raise exception 'A reason is required when changing environment mode.';
  end if;

  select r.enabled into previous_enabled
  from public.hms_test_runtime r
  where r.id = true
  for update;

  if previous_enabled is null then
    raise exception 'Test runtime configuration is unavailable.';
  end if;

  if previous_enabled = _enabled then
    return query
    select r.enabled, r.updated_at
    from public.hms_test_runtime r
    where r.id = true;
    return;
  end if;

  next_updated_at := now();

  update public.hms_test_runtime
  set enabled = _enabled, updated_at = next_updated_at
  where id = true;

  insert into public.hms_test_runtime_audit (
    changed_by, previous_enabled, new_enabled, reason, changed_at
  ) values (
    actor, previous_enabled, _enabled, normalized_reason, next_updated_at
  );

  return query
  select _enabled, next_updated_at;
end;
$$;

revoke all on function public.get_hms_test_runtime_status() from public, anon;
revoke all on function public.set_hms_test_runtime(boolean, text) from public, anon;
grant execute on function public.get_hms_test_runtime_status() to authenticated;
grant execute on function public.set_hms_test_runtime(boolean, text) to authenticated;

comment on function public.get_hms_test_runtime_status() is
'Returns the explicit test runtime switch for system super administrators only.';

comment on function public.set_hms_test_runtime(boolean, text) is
'Changes the explicit test runtime switch for system super administrators only and records an audit event.';

comment on table public.hms_test_runtime_audit is
'Auditable history of explicit test-mode changes. Test mode must be disabled before final production release.';
