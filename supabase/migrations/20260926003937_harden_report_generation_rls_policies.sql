-- Consolidate duplicate report-generation RLS policies and enforce facility scope
-- on report-generation updates while preserving creator/admin workflow authority.

drop policy if exists items_update on public.report_generation_items;
drop policy if exists report_generation_items_update on public.report_generation_items;

create policy report_generation_items_update
on public.report_generation_items
as permissive
for update
to authenticated
using (
  exists (
    select 1
    from public.report_generation_runs r
    where r.id = report_generation_items.run_id
      and current_user_has_facility_access(r.facility_id)
      and (
        r.created_by = (select auth.uid())
        or current_user_has_role('admin'::public.app_role)
      )
  )
)
with check (
  exists (
    select 1
    from public.report_generation_runs r
    where r.id = report_generation_items.run_id
      and current_user_has_facility_access(r.facility_id)
      and (
        r.created_by = (select auth.uid())
        or current_user_has_role('admin'::public.app_role)
      )
  )
);

drop policy if exists items_access on public.report_generation_items;

drop policy if exists report_generation_runs_insert on public.report_generation_runs;
drop policy if exists runs_insert on public.report_generation_runs;

create policy report_generation_runs_insert
on public.report_generation_runs
as permissive
for insert
to authenticated
with check (
  current_user_has_facility_access(facility_id)
  and created_by = (select auth.uid())
);

drop policy if exists report_generation_runs_access on public.report_generation_runs;
drop policy if exists runs_access on public.report_generation_runs;

create policy report_generation_runs_access
on public.report_generation_runs
as permissive
for select
to authenticated
using (current_user_has_facility_access(facility_id));

drop policy if exists report_generation_runs_update on public.report_generation_runs;
drop policy if exists runs_update on public.report_generation_runs;

create policy report_generation_runs_update
on public.report_generation_runs
as permissive
for update
to authenticated
using (
  current_user_has_facility_access(facility_id)
  and (
    created_by = (select auth.uid())
    or current_user_has_role('admin'::public.app_role)
  )
)
with check (
  current_user_has_facility_access(facility_id)
  and (
    created_by = (select auth.uid())
    or current_user_has_role('admin'::public.app_role)
  )
);