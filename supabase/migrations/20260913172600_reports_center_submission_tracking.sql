-- Preserve submission lifecycle state when a report is regenerated.
-- A regeneration may refresh the due date and data snapshot, but must never
-- silently reset submitted/accepted/rejected records to pending.

create or replace function public.upsert_report_submission_tracking(
  _report_id uuid,
  _facility_id uuid,
  _period_start date,
  _period_end date,
  _due_date date,
  _data_snapshot jsonb
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_count integer := 0;
begin
  if v_user is null then
    raise exception 'Authentication is required.' using errcode = '42501';
  end if;

  if not public.has_facility_access(v_user, _facility_id) then
    raise exception 'You do not have access to this facility' using errcode = '42501';
  end if;

  insert into public.report_submissions (
    report_id,
    facility_id,
    period_start,
    period_end,
    due_date,
    status,
    data_snapshot
  )
  values (
    _report_id,
    _facility_id,
    _period_start,
    _period_end,
    _due_date,
    'pending',
    _data_snapshot
  )
  on conflict (report_id, facility_id, period_start, period_end)
  do update set
    due_date = excluded.due_date,
    data_snapshot = excluded.data_snapshot,
    updated_at = now();

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke all on function public.upsert_report_submission_tracking(uuid, uuid, date, date, date, jsonb) from public;
grant execute on function public.upsert_report_submission_tracking(uuid, uuid, date, date, date, jsonb) to authenticated;
