-- Prevent clinicians from using department queues as if they were departmental operators.
-- Admin and IT Admin retain troubleshooting access; all other roles must match the queue department.

create or replace function public.get_department_queue(_department text, _limit integer default 100)
returns table(
  id uuid, department text, status text, queued_at timestamptz, service_order_id uuid,
  service_name text, amount numeric, service_order_status text, patient_id uuid,
  patient_first_name text, patient_last_name text, patient_code text
)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_department text := nullif(pg_catalog.btrim(_department),'');
  v_role public.app_role;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if v_department is null then return; end if;
  if _limit is null or _limit < 1 or _limit > 500 then raise exception 'Invalid queue limit'; end if;

  if public.has_role(auth.uid(),'admin') or public.has_role(auth.uid(),'it_admin') then
    null;
  else
    select ur.role into v_role
    from public.user_roles ur
    where ur.user_id = auth.uid()
    order by ur.created_at asc
    limit 1;

    if v_role is null then raise exception 'Department queue access denied'; end if;

    if lower(v_department) in ('laboratory','lab','pathology') and v_role <> 'lab_technician' then
      raise exception 'Department queue access denied for laboratory role';
    elsif lower(v_department) in ('radiology','imaging') and v_role not in ('radiologist','radiology_technician') then
      raise exception 'Department queue access denied for imaging role';
    elsif lower(v_department) in ('pharmacy','dispensary') and v_role <> 'pharmacist' then
      raise exception 'Department queue access denied for pharmacy role';
    elsif lower(v_department) in ('accounts','accounting','finance') and v_role <> 'accountant' then
      raise exception 'Department queue access denied for accounts role';
    elsif lower(v_department) in ('canteen','dietary') and v_role <> 'canteen' then
      raise exception 'Department queue access denied for canteen role';
    elsif lower(v_department) in ('front desk','front_desk','reception') and v_role <> 'front_desk' then
      raise exception 'Department queue access denied for front desk role';
    elsif lower(v_department) in ('nursing','inpatient') and v_role not in ('nurse','specialist_nurse','midwife') then
      raise exception 'Department queue access denied for nursing role';
    elsif lower(v_department) not in ('laboratory','lab','pathology','radiology','imaging','pharmacy','dispensary','accounts','accounting','finance','canteen','dietary','front desk','front_desk','reception','nursing','inpatient') then
      raise exception 'Department queue is not an operational role queue';
    end if;

    if not exists (
      select 1 from public.profiles p
      where p.id=auth.uid() and lower(coalesce(p.department,''))=lower(v_department)
    ) then
      raise exception 'Department queue access denied for this department';
    end if;
  end if;

  return query
  select q.id,q.department,q.status,q.queued_at,q.service_order_id,so.service_name,so.amount,
         so.status,so.patient_id,p.first_name,p.last_name,p.patient_code
  from public.department_queues q
  join public.service_orders so on so.id=q.service_order_id
  join public.patients p on p.id=so.patient_id
  where lower(q.department)=lower(v_department)
    and q.status in ('queued','claimed')
  order by q.queued_at asc
  limit _limit;
end;
$$;

revoke all on function public.get_department_queue(text,integer) from public, anon;
grant execute on function public.get_department_queue(text,integer) to authenticated;
