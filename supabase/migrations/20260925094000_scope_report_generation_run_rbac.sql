-- Reconcile Reports Center generation-run reads with the scoped current-user
-- authorization boundary. Raw arbitrary-user helpers remain internal.
drop policy if exists report_generation_runs_access on public.report_generation_runs;
create policy report_generation_runs_access on public.report_generation_runs
  for select to authenticated
  using (public.current_user_has_facility_access(facility_id));

drop policy if exists report_generation_runs_insert on public.report_generation_runs;
create policy report_generation_runs_insert on public.report_generation_runs
  for insert to authenticated
  with check (
    public.current_user_has_facility_access(facility_id)
    and created_by = (select auth.uid())
  );

drop policy if exists report_generation_runs_update on public.report_generation_runs;
create policy report_generation_runs_update on public.report_generation_runs
  for update to authenticated
  using (
    public.current_user_has_facility_access(facility_id)
    and created_by = (select auth.uid())
  )
  with check (
    public.current_user_has_facility_access(facility_id)
    and created_by = (select auth.uid())
  );

-- Child generation-item policies must resolve facility access through the same
-- scoped wrapper rather than the raw arbitrary-user helper.
drop policy if exists report_generation_items_access on public.report_generation_items;
create policy report_generation_items_access on public.report_generation_items
  for select to authenticated
  using (
    exists (
      select 1
      from public.report_generation_runs r
      where r.id = run_id
        and public.current_user_has_facility_access(r.facility_id)
    )
  );

drop policy if exists report_generation_items_update on public.report_generation_items;
create policy report_generation_items_update on public.report_generation_items
  for update to authenticated
  using (
    exists (
      select 1
      from public.report_generation_runs r
      where r.id = run_id
        and public.current_user_has_facility_access(r.facility_id)
        and r.created_by = (select auth.uid())
    )
  )
  with check (
    exists (
      select 1
      from public.report_generation_runs r
      where r.id = run_id
        and public.current_user_has_facility_access(r.facility_id)
        and r.created_by = (select auth.uid())
    )
  );
