-- Performance hardening for canonical insurance master-data RLS.
-- Wrap auth.uid() in scalar subqueries so the value is initialized once per statement.
-- Split the tariff ALL policy so SELECT is not evaluated through multiple permissive policies.

drop policy if exists insurance_companies_admin_it_read on public.insurance_companies;
create policy insurance_companies_admin_it_read on public.insurance_companies
for select to authenticated
using (
  public.has_role((select auth.uid()), 'admin'::public.app_role)
  or public.has_role((select auth.uid()), 'it_admin'::public.app_role)
);

drop policy if exists insurance_service_tariffs_admin_read on public.insurance_service_tariffs;
create policy insurance_service_tariffs_admin_read on public.insurance_service_tariffs
for select to authenticated
using (
  public.has_role((select auth.uid()), 'admin'::public.app_role)
  or public.has_role((select auth.uid()), 'accountant'::public.app_role)
);

drop policy if exists insurance_service_tariffs_admin_write on public.insurance_service_tariffs;
create policy insurance_service_tariffs_admin_insert on public.insurance_service_tariffs
for insert to authenticated
with check (public.has_role((select auth.uid()), 'admin'::public.app_role));

create policy insurance_service_tariffs_admin_update on public.insurance_service_tariffs
for update to authenticated
using (public.has_role((select auth.uid()), 'admin'::public.app_role))
with check (public.has_role((select auth.uid()), 'admin'::public.app_role));

create policy insurance_service_tariffs_admin_delete on public.insurance_service_tariffs
for delete to authenticated
using (public.has_role((select auth.uid()), 'admin'::public.app_role));
