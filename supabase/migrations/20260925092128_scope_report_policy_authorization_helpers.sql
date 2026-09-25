-- Scope client-visible RBAC policy evaluation to the authenticated session.
create or replace function public.current_user_has_role(_role public.app_role)
returns boolean
language sql
stable
security definer
set search_path = public
as $function$
  select public.has_role(auth.uid(), _role);
$function$;

revoke all on function public.current_user_has_role(public.app_role) from public, anon;
grant execute on function public.current_user_has_role(public.app_role) to authenticated;

drop policy if exists permissions_admin_delete on public.permissions;
drop policy if exists permissions_admin_insert on public.permissions;
drop policy if exists permissions_admin_update on public.permissions;
drop policy if exists permissions_authenticated_read on public.permissions;

create policy permissions_admin_delete on public.permissions for delete to authenticated
using (public.current_user_has_role('admin'::public.app_role));
create policy permissions_admin_insert on public.permissions for insert to authenticated
with check (public.current_user_has_role('admin'::public.app_role));
create policy permissions_admin_update on public.permissions for update to authenticated
using (public.current_user_has_role('admin'::public.app_role))
with check (public.current_user_has_role('admin'::public.app_role));
create policy permissions_authenticated_read on public.permissions for select to authenticated
using (is_active or public.current_user_has_role('admin'::public.app_role));

drop policy if exists role_permissions_admin_delete on public.role_permissions;
drop policy if exists role_permissions_admin_insert on public.role_permissions;
drop policy if exists role_permissions_admin_update on public.role_permissions;
drop policy if exists role_permissions_read_own on public.role_permissions;

create policy role_permissions_admin_delete on public.role_permissions for delete to authenticated
using (public.current_user_has_role('admin'::public.app_role));
create policy role_permissions_admin_insert on public.role_permissions for insert to authenticated
with check (public.current_user_has_role('admin'::public.app_role));
create policy role_permissions_admin_update on public.role_permissions for update to authenticated
using (public.current_user_has_role('admin'::public.app_role))
with check (public.current_user_has_role('admin'::public.app_role));
create policy role_permissions_read_own on public.role_permissions for select to authenticated
using (
  role in (select ur.role from public.user_roles ur where ur.user_id=(select auth.uid()))
  or public.current_user_has_role('admin'::public.app_role)
);

drop policy if exists config_admin_insert on public.facility_report_config;
drop policy if exists config_admin_update on public.facility_report_config;
drop policy if exists config_admin_delete on public.facility_report_config;

create policy config_admin_insert on public.facility_report_config for insert to authenticated
with check (public.current_user_has_role('admin'::public.app_role));
create policy config_admin_update on public.facility_report_config for update to authenticated
using (public.current_user_has_role('admin'::public.app_role))
with check (public.current_user_has_role('admin'::public.app_role));
create policy config_admin_delete on public.facility_report_config for delete to authenticated
using (public.current_user_has_role('admin'::public.app_role));
