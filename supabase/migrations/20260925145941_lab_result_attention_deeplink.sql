-- Keep laboratory result attention actionable after approval.
-- The existing approval workflow remains server-authoritative; this migration only
-- corrects the notification destination so the ordering clinician lands in the
-- laboratory workspace with the relevant patient/order/result context.

create or replace function public.approve_lab_result(_lab_result_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  uid uuid := auth.uid();
  r public.lab_results%rowtype;
  o public.lab_orders%rowtype;
begin
  if uid is null or not (
    public.has_role(uid,'admin')
    or public.has_role(uid,'lab_technician')
    or public.has_role(uid,'practitioner')
  ) then
    raise exception 'Laboratory approval role required';
  end if;

  select * into r
  from public.lab_results
  where id=_lab_result_id
  for update;

  if not found then
    raise exception 'Laboratory result not found';
  end if;

  if r.status<>'completed' then
    raise exception 'Only completed results can be approved';
  end if;

  select * into o
  from public.lab_orders
  where id=r.lab_order_id
  for update;

  if not found then
    raise exception 'Laboratory order not found';
  end if;

  if o.status<>'completed' then
    raise exception 'Laboratory order must be completed before result approval';
  end if;

  update public.lab_results
  set status='approved',
      approved_by=uid,
      approved_at=now(),
      updated_at=now()
  where id=r.id
    and status='completed';

  update public.lab_orders
  set status='approved',
      updated_at=now()
  where id=o.id
    and status='completed';

  if o.ordered_by is not null and not exists (
    select 1
    from public.notifications
    where recipient_user_id=o.ordered_by
      and related_entity_id=o.id
      and category='diagnostic_result'
      and title='Laboratory result ready'
      and is_read=false
  ) then
    insert into public.notifications(
      recipient_user_id,
      title,
      message,
      severity,
      category,
      link,
      related_patient_id,
      related_entity_id,
      metadata
    )
    values(
      o.ordered_by,
      'Laboratory result ready',
      format('The %s laboratory result is approved and ready for clinical review.',o.test_name),
      case when coalesce(r.is_abnormal,false) then 'critical' else 'info' end,
      'diagnostic_result',
      format(
        '/laboratory?patient=%s&order=%s&result=%s%s',
        o.patient_id,
        o.id,
        r.id,
        case when o.encounter_id is not null then format('&encounter=%s',o.encounter_id) else '' end
      ),
      o.patient_id,
      o.id,
      jsonb_build_object(
        'workflow','lab_result_review',
        'lab_result_id',r.id,
        'lab_order_id',o.id,
        'encounter_id',o.encounter_id,
        'is_abnormal',coalesce(r.is_abnormal,false),
        'requires_acknowledgement',true
      )
    );
  end if;

  return jsonb_build_object(
    'lab_result_id',r.id,
    'lab_order_id',o.id,
    'encounter_id',o.encounter_id,
    'status','approved'
  );
end;
$function$;

revoke all on function public.approve_lab_result(uuid) from public, anon;
grant execute on function public.approve_lab_result(uuid) to authenticated;
