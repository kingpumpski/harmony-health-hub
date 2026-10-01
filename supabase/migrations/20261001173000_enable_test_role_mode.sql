-- Temporary role-testing mode for the current non-production test environment.
-- Production/final deployments must disable hms_test_runtime.enabled.
create table if not exists public.hms_test_runtime (
  id boolean primary key default true check (id = true),
  enabled boolean not null default false,
  updated_at timestamptz not null default now()
);

create table if not exists public.hms_test_users (
  user_id uuid primary key references auth.users(id) on delete cascade,
  enabled boolean not null default true,
  reason text not null default 'Role testing account',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.hms_test_runtime enable row level security;
alter table public.hms_test_users enable row level security;
revoke all on public.hms_test_runtime from public, anon, authenticated;
revoke all on public.hms_test_users from public, anon, authenticated;

insert into public.hms_test_runtime(id, enabled)
values (true, true)
on conflict (id) do update set enabled = true, updated_at = now();

insert into public.hms_test_users(user_id)
select distinct ur.user_id
from public.user_roles ur
where ur.user_id is not null
on conflict (user_id) do update set enabled = true, updated_at = now();

create or replace function public.hms_test_mode_enabled()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((select r.enabled from public.hms_test_runtime r where r.id = true), false);
$$;

create or replace function public.hms_current_user_is_test_user()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    (select auth.uid()) is not null
    and (select public.hms_test_mode_enabled())
    and exists (
      select 1
      from public.hms_test_users tu
      where tu.user_id = (select auth.uid())
        and tu.enabled = true
    );
$$;

create or replace function public.hms_test_facility_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select hf.id
  from public.healthcare_facilities hf
  where hf.facility_code = 'TEST-0001'
    and hf.is_active = true
  order by hf.id
  limit 1;
$$;

insert into public.healthcare_facilities
  (name, facility_code, facility_type, district, region, is_active)
select
  'Harmony Health Hub Test Facility',
  'TEST-0001',
  'other',
  'Test Environment',
  'Test Environment',
  true
where not exists (
  select 1 from public.healthcare_facilities hf where hf.facility_code = 'TEST-0001'
);

create or replace function public.current_user_facility_id()
returns uuid
language sql
stable
security definer
set search_path = 'pg_catalog, public'
as $$
  select case
    when public.hms_current_user_is_test_user()
      then public.hms_test_facility_id()
    else coalesce(
      (select uaf.facility_id
       from public.user_active_facilities uaf
       join public.facility_memberships fm
         on fm.user_id=uaf.user_id
        and fm.facility_id=uaf.facility_id
        and fm.is_active=true
       where uaf.user_id=(select auth.uid())
         and exists (
           select 1 from public.healthcare_facilities hf
           where hf.id=uaf.facility_id and hf.is_active=true
         )
       limit 1),
      (select fm.facility_id
       from public.facility_memberships fm
       join public.healthcare_facilities hf
         on hf.id=fm.facility_id and hf.is_active=true
       where fm.user_id=(select auth.uid()) and fm.is_active=true
       group by fm.facility_id
       having count(*)=1
       order by fm.facility_id
       limit 1)
    )
  end;
$$;

create or replace function public.has_facility_access(_user_id uuid, _facility_id uuid)
returns boolean
language sql
stable
security definer
set search_path = 'pg_catalog, public'
as $$
  select
    (
      _facility_id is not null
      and exists (
        select 1
        from public.hms_test_users tu
        where tu.user_id=_user_id and tu.enabled=true
      )
      and public.hms_test_mode_enabled()
      and _facility_id=public.hms_test_facility_id()
    )
    or exists (
      select 1 from public.user_roles ur
      where ur.user_id = _user_id and ur.role = 'system_superuser'::public.app_role
    )
    or exists (
      select 1
      from public.user_active_facilities uaf
      join public.facility_memberships fm
        on fm.user_id = uaf.user_id
       and fm.facility_id = uaf.facility_id
       and fm.is_active = true
      join public.healthcare_facilities hf
        on hf.id = uaf.facility_id
       and hf.is_active = true
      where uaf.user_id = _user_id
        and uaf.facility_id = _facility_id
    )
    or (
      (select count(*) from public.facility_memberships fm where fm.user_id = _user_id and fm.is_active = true) = 1
      and exists (
        select 1
        from public.facility_memberships fm
        join public.healthcare_facilities hf on hf.id = fm.facility_id and hf.is_active = true
        where fm.user_id = _user_id and fm.facility_id = _facility_id and fm.is_active = true
      )
    );
$$;

create or replace function public.current_user_has_facility_access(_facility_id uuid)
returns boolean
language sql
stable
security definer
set search_path = 'pg_catalog, public'
as $$
  select
    (
      (select public.hms_current_user_is_test_user())
      and (_facility_id is null or _facility_id = public.hms_test_facility_id())
    )
    or public.has_facility_access((select auth.uid()), _facility_id)
    or (
      (select auth.uid()) is not null
      and private.current_user_has_facility_data_scope(_facility_id,'patient_read')
    );
$$;

revoke all on function public.hms_test_mode_enabled() from public, anon;
grant execute on function public.hms_test_mode_enabled() to authenticated;
revoke all on function public.hms_current_user_is_test_user() from public, anon;
grant execute on function public.hms_current_user_is_test_user() to authenticated;
revoke all on function public.hms_test_facility_id() from public, anon;
grant execute on function public.hms_test_facility_id() to authenticated;

comment on table public.hms_test_runtime is
  'Explicit non-production test switch. Must be false before final/production operation.';
comment on table public.hms_test_users is
  'Explicit allowlist of test accounts eligible for temporary test-mode facility context.';
