-- Super-admin-only UI control for the explicit non-production test mode.
-- Production-safe by default: environment='production' blocks the toggle.

alter table public.hms_test_runtime
  add column if not exists environment text not null default 'production'
    check (environment in ('test','production'));

create table if not exists public.hms_test_runtime_audit (
  id uuid primary key default gen_random_uuid(),
  actor_user_id uuid not null references auth.users(id),
  previous_enabled boolean not null,
  new_enabled boolean not null,
  environment text not null,
  reason text not null,
  created_at timestamptz not null default now()
);

alter table public.hms_test_runtime_audit enable row level security;
revoke all on public.hms_test_runtime_audit from public, anon, authenticated;

drop function if exists public.get_hms_test_runtime_status();
drop function if exists public.set_hms_test_runtime(boolean,text);

create or replace function public.get_hms_test_runtime_status()
returns table(enabled boolean, environment text, updated_at timestamptz)
language plpgsql
stable
security definer
set search_path = 'pg_catalog, public'
as $$
begin
  if (select auth.uid()) is null then raise exception 'Authentication required'; end if;
  if not exists (
    select 1 from public.user_roles ur
    where ur.user_id = (select auth.uid())
      and ur.role = 'system_superuser'::public.app_role
  ) then raise exception 'System superuser access required'; end if;
  return query select r.enabled, r.environment, r.updated_at
  from public.hms_test_runtime r where r.id = true;
end;
$$;

create or replace function public.set_hms_test_runtime(_enabled boolean,_reason text)
returns table(enabled boolean, environment text, updated_at timestamptz)
language plpgsql
security definer
set search_path = 'pg_catalog, public'
as $$
declare v_previous boolean; v_environment text;
begin
  if (select auth.uid()) is null then raise exception 'Authentication required'; end if;
  if not exists (
    select 1 from public.user_roles ur
    where ur.user_id = (select auth.uid())
      and ur.role = 'system_superuser'::public.app_role
  ) then raise exception 'System superuser access required'; end if;
  if nullif(trim(coalesce(_reason,'')), '') is null then
    raise exception 'A reason is required for every test-mode change';
  end if;
  select r.enabled, r.environment into v_previous, v_environment
  from public.hms_test_runtime r where r.id = true for update;
  if not found then raise exception 'Test runtime configuration is unavailable'; end if;
  if v_environment <> 'test' then
    raise exception 'Test mode switching is disabled for production deployments';
  end if;
  update public.hms_test_runtime set enabled=coalesce(_enabled,false), updated_at=now()
  where id=true
  returning hms_test_runtime.enabled, hms_test_runtime.environment, hms_test_runtime.updated_at
  into enabled, environment, updated_at;
  insert into public.hms_test_runtime_audit(actor_user_id,previous_enabled,new_enabled,environment,reason)
  values ((select auth.uid()),v_previous,enabled,environment,trim(_reason));
  return next;
end;
$$;

revoke all on function public.get_hms_test_runtime_status() from public, anon, authenticated;
grant execute on function public.get_hms_test_runtime_status() to authenticated;
revoke all on function public.set_hms_test_runtime(boolean,text) from public, anon, authenticated;
grant execute on function public.set_hms_test_runtime(boolean,text) to authenticated;

comment on column public.hms_test_runtime.environment is 'Deployment guard for test mode. Production is the safe default; only test permits the super-admin toggle.';
comment on table public.hms_test_runtime_audit is 'Audit trail for super-admin test-mode changes; direct table access is revoked.';

notify pgrst, 'reload schema';
