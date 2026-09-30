-- Harden department queue authorization for multi-role users and canonical department aliases.
-- A user's first role must never determine queue authorization when multiple roles exist.

create or replace function public.get_department_queue(
  _department text,
  _limit integer default 100
)
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
  v_department_key text;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if v_department is null then return; end if;
  if _limit is null or _limit < 1 or _limit > 500 then raise exception 'Invalid queue limit'; end if;

  v_department_key := lower(regexp_replace(v_department, '[[:space:]_-]+', ' ', 'g'));

  if public.has_role(auth.uid(),'admin') or public.has_role(auth.uid(),'it_admin') then
    null;
  elsif v_department_key in ('laboratory','lab','pathology') then
    if not exists (
      select 1 from public.user_roles ur
      where ur.user_id=auth.uid() and ur.role='lab_technician'
    ) then raise exception 'Department queue access denied for laboratory role'; end if;
    if not exists (
      select 1 from public.profiles p
      where p.id=auth.uid()
        and lower(regexp_replace(coalesce(p.department,''), '[[:space:]_-]+', ' ', 'g')) in ('laboratory','lab','pathology')
    ) then raise exception 'Department queue access denied for this department'; end if;
  elsif v_department_key in ('radiology','imaging') then
    if not exists (
      select 1 from public.user_roles ur
      where ur.user_id=auth.uid() and ur.role in ('radiologist','radiology_technician')
    ) then raise exception 'Department queue access denied for imaging role'; end if;
    if not exists (
      select 1 from public.profiles p
      where p.id=auth.uid()
        and lower(regexp_replace(coalesce(p.department,''), '[[:space:]_-]+', ' ', 'g')) in ('radiology','imaging')
    ) then raise exception 'Department queue access denied for this department'; end if;
  elsif v_department_key in ('pharmacy','dispensary') then
    if not exists (select 1 from public.user_roles ur where ur.user_id=auth.uid() and ur.role='pharmacist') then
      raise exception 'Department queue access denied for pharmacy role';
    end if;
    if not exists (select 1 from public.profiles p where p.id=auth.uid() and lower(regexp_replace(coalesce(p.department,''), '[[:space:]_-]+', ' ', 'g')) in ('pharmacy','dispensary')) then
      raise exception 'Department queue access denied for this department';
    end if;
  elsif v_department_key in ('accounts','accounting','finance') then
    if not exists (select 1 from public.user_roles ur where ur.user_id=auth.uid() and ur.role='accountant') then
      raise exception 'Department queue access denied for accounts role';
    end if;
    if not exists (select 1 from public.profiles p where p.id=auth.uid() and lower(regexp_replace(coalesce(p.department,''), '[[:space:]_-]+', ' ', 'g')) in ('accounts','accounting','finance')) then
      raise exception 'Department queue access denied for this department';
    end if;
  elsif v_department_key in ('canteen','dietary') then
    if not exists (select 1 from public.user_roles ur where ur.user_id=auth.uid() and ur.role='canteen') then
      raise exception 'Department queue access denied for canteen role';
    end if;
    if not exists (select 1 from public.profiles p where p.id=auth.uid() and lower(regexp_replace(coalesce(p.department,''), '[[:space:]_-]+', ' ', 'g')) in ('canteen','dietary')) then
      raise exception 'Department queue access denied for this department';
    end if;
  elsif v_department_key in ('front desk','reception') then
    if not exists (select 1 from public.user_roles ur where ur.user_id=auth.uid() and ur.role='front_desk') then
      raise exception 'Department queue access denied for front desk role';
    end if;
    if not exists (select 1 from public.profiles p where p.id=auth.uid() and lower(regexp_replace(coalesce(p.department,''), '[[:space:]_-]+', ' ', 'g')) in ('front desk','reception')) then
      raise exception 'Department queue access denied for this department';
    end if;
  elsif v_department_key in ('nursing','inpatient') then
    if not exists (select 1 from public.user_roles ur where ur.user_id=auth.uid() and ur.role in ('nurse','specialist_nurse','midwife')) then
      raise exception 'Department queue access denied for nursing role';
    end if;
    if not exists (select 1 from public.profiles p where p.id=auth.uid() and lower(regexp_replace(coalesce(p.department,''), '[[:space:]_-]+', ' ', 'g')) in ('nursing','inpatient')) then
      raise exception 'Department queue access denied for this department';
    end if;
  else
    raise exception 'Department queue is not an operational role queue';
  end if;

  return query
  select q.id,q.department,q.status,q.queued_at,q.service_order_id,so.service_name,so.amount,
         so.status,so.patient_id,p.first_name,p.last_name,p.patient_code
  from public.department_queues q
  join public.service_orders so on so.id=q.service_order_id
  join public.patients p on p.id=so.patient_id
  where lower(regexp_replace(q.department, '[[:space:]_-]+', ' ', 'g')) = v_department_key
    and q.status in ('queued','claimed')
  order by q.queued_at asc
  limit _limit;
end;
$$;

revoke all on function public.get_department_queue(text,integer) from public, anon;
grant execute on function public.get_department_queue(text,integer) to authenticated;
