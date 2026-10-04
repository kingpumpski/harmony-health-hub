-- Reconcile platform superuser access and preserve compatibility with older facility-directory clients.
insert into public.user_roles (user_id, role)
select p.id, 'system_superuser'::public.app_role
from public.profiles p
where lower(p.email) = lower('pumpski6@gmail.com')
  and not exists (
    select 1 from public.user_roles ur
    where ur.user_id = p.id and ur.role = 'system_superuser'::public.app_role
  );

insert into public.role_permissions (role, permission_key)
select 'system_superuser'::public.app_role, p.permission_key
from public.permissions p
where p.is_active
  and not exists (
    select 1 from public.role_permissions rp
    where rp.role = 'system_superuser'::public.app_role
      and rp.permission_key = p.permission_key
  );

drop function if exists public.platform_list_facilitys();

create or replace function public.platform_list_facilitys()
returns table(id uuid, name text, facility_code text, facility_type text, district text, region text, is_active boolean, created_at timestamptz)
language plpgsql
stable
security definer
set search_path = ''
as $function$
begin
  if not exists (
    select 1 from public.user_roles ur
    where ur.user_id = (select auth.uid())
      and ur.role = 'system_superuser'::public.app_role
  ) then
    raise exception 'Only system super administrators may view platform facilities';
  end if;
  return query
    select hf.id, hf.name, hf.facility_code, hf.facility_type, hf.district, hf.region, hf.is_active, hf.created_at
    from public.healthcare_facilities hf
    order by hf.created_at desc;
end;
$function$;

revoke all on function public.platform_list_facilitys() from public;
revoke all on function public.platform_list_facilitys() from anon;
revoke all on function public.platform_list_facilitys() from authenticated;
grant execute on function public.platform_list_facilitys() to authenticated;
notify pgrst, 'reload schema';
