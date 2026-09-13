-- Harden Reports Center submission workflow so client callers cannot move
-- terminal submission states (accepted/rejected) back to submitted.

create or replace function public.mark_report_submissions_submitted(_submission_ids uuid[])
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_updated integer := 0;
begin
  if v_user is null then
    raise exception 'Authentication is required.' using errcode = '42501';
  end if;

  update public.report_submissions as rs
  set
    status = 'submitted',
    submitted_at = now(),
    submitted_by = v_user,
    updated_at = now()
  where rs.id = any(coalesce(_submission_ids, '{}'::uuid[]))
    and rs.status in ('pending', 'overdue')
    and public.has_facility_access(v_user, rs.facility_id);

  get diagnostics v_updated = row_count;
  return v_updated;
end;
$$;

revoke execute on function public.mark_report_submissions_submitted(uuid[]) from public;
grant execute on function public.mark_report_submissions_submitted(uuid[]) to authenticated;
