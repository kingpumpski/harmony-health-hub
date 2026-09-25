create or replace function public.current_user_has_facility_access(_facility_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $function$
  select public.has_facility_access(auth.uid(), _facility_id);
$function$;

create or replace function public.current_user_has_role(_role public.app_role)
returns boolean
language sql
stable
security definer
set search_path = public
as $function$
  select public.has_role(auth.uid(), _role);
$function$;

revoke all on function public.current_user_has_facility_access(uuid) from public, anon;
revoke all on function public.current_user_has_role(public.app_role) from public, anon;
grant execute on function public.current_user_has_facility_access(uuid) to authenticated;
grant execute on function public.current_user_has_role(public.app_role) to authenticated;

drop policy if exists config_access on public.facility_report_config;
drop policy if exists config_admin_insert on public.facility_report_config;
drop policy if exists config_admin_update on public.facility_report_config;
drop policy if exists config_admin_delete on public.facility_report_config;

create policy config_access
on public.facility_report_config
for select
to authenticated
using (public.current_user_has_facility_access(facility_id));

create policy config_admin_insert
on public.facility_report_config
for insert
to authenticated
with check (public.current_user_has_role('admin'::public.app_role));

create policy config_admin_update
on public.facility_report_config
for update
to authenticated
using (public.current_user_has_role('admin'::public.app_role))
with check (public.current_user_has_role('admin'::public.app_role));

create policy config_admin_delete
on public.facility_report_config
for delete
to authenticated
using (public.current_user_has_role('admin'::public.app_role));

revoke execute on function public.has_facility_access(uuid, uuid) from authenticated;
revoke execute on function public.has_role(uuid, public.app_role) from authenticated;
