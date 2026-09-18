-- Workflow-safe staff directory and notification bridge.
-- Keeps patient/notification RLS strict while giving authorized staff modules
-- a controlled server-side read/write boundary.

create or replace function public.search_patient_directory(
  _query text default null,
  _limit integer default 300
)
returns table (
  id uuid,
  patient_code text,
  first_name text,
  last_name text,
  phone text,
  ghana_card_number text,
  status text,
  insurance_provider text,
  insurance_number text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  q text := nullif(trim(coalesce(_query, '')), '');
  lim integer := least(greatest(coalesce(_limit, 100), 1), 1000);
begin
  if not (
    has_role(auth.uid(), 'admin'::app_role)
    or has_role(auth.uid(), 'practitioner'::app_role)
    or has_role(auth.uid(), 'nurse'::app_role)
    or has_role(auth.uid(), 'midwife'::app_role)
    or has_role(auth.uid(), 'specialist_nurse'::app_role)
    or has_role(auth.uid(), 'lab_technician'::app_role)
    or has_role(auth.uid(), 'radiologist'::app_role)
    or has_role(auth.uid(), 'pharmacist'::app_role)
    or has_role(auth.uid(), 'accountant'::app_role)
    or has_role(auth.uid(), 'front_desk'::app_role)
    or has_role(auth.uid(), 'canteen'::app_role)
  ) then
    raise exception 'Not authorized to access the staff patient directory';
  end if;

  return query
  select p.id, p.patient_code, p.first_name, p.last_name, p.phone,
         p.ghana_card_number, p.status::text, p.insurance_provider,
         p.insurance_number
  from public.patients p
  where q is null
     or p.patient_code ilike '%' || q || '%'
     or p.first_name ilike '%' || q || '%'
     or p.last_name ilike '%' || q || '%'
     or p.phone ilike '%' || q || '%'
     or p.ghana_card_number ilike '%' || q || '%'
     or p.email ilike '%' || q || '%'
  order by p.created_at desc
  limit lim;
end;
$$;

create or replace function public.get_patient_directory_record(_patient_id uuid)
returns table (
  id uuid,
  patient_code text,
  first_name text,
  last_name text,
  phone text,
  ghana_card_number text,
  status text,
  insurance_provider text,
  insurance_number text
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not (
    has_role(auth.uid(), 'admin'::app_role)
    or has_role(auth.uid(), 'practitioner'::app_role)
    or has_role(auth.uid(), 'nurse'::app_role)
    or has_role(auth.uid(), 'midwife'::app_role)
    or has_role(auth.uid(), 'specialist_nurse'::app_role)
    or has_role(auth.uid(), 'lab_technician'::app_role)
    or has_role(auth.uid(), 'radiologist'::app_role)
    or has_role(auth.uid(), 'pharmacist'::app_role)
    or has_role(auth.uid(), 'accountant'::app_role)
    or has_role(auth.uid(), 'front_desk'::app_role)
    or has_role(auth.uid(), 'canteen'::app_role)
  ) then
    raise exception 'Not authorized to access the staff patient directory';
  end if;

  return query
  select p.id, p.patient_code, p.first_name, p.last_name, p.phone,
         p.ghana_card_number, p.status::text, p.insurance_provider,
         p.insurance_number
  from public.patients p
  where p.id = _patient_id;
end;
$$;

create or replace function public.create_workflow_notification(
  _recipient_role text default null,
  _recipient_user_id uuid default null,
  _title text default '',
  _message text default '',
  _severity text default 'info',
  _category text default 'other',
  _link text default null,
  _related_patient_id uuid default null,
  _related_entity_id uuid default null,
  _metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  new_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if not (
    has_role(auth.uid(), 'admin'::app_role)
    or has_role(auth.uid(), 'practitioner'::app_role)
    or has_role(auth.uid(), 'nurse'::app_role)
    or has_role(auth.uid(), 'midwife'::app_role)
    or has_role(auth.uid(), 'specialist_nurse'::app_role)
    or has_role(auth.uid(), 'lab_technician'::app_role)
    or has_role(auth.uid(), 'radiologist'::app_role)
    or has_role(auth.uid(), 'pharmacist'::app_role)
    or has_role(auth.uid(), 'accountant'::app_role)
    or has_role(auth.uid(), 'front_desk'::app_role)
    or has_role(auth.uid(), 'canteen'::app_role)
  ) then
    raise exception 'Not authorized to create workflow notifications';
  end if;

  insert into public.notifications (
    recipient_role, recipient_user_id, title, message, severity, category,
    link, related_patient_id, related_entity_id, metadata
  )
  values (
    nullif(_recipient_role, ''), _recipient_user_id, _title, _message,
    coalesce(nullif(_severity, ''), 'info'),
    coalesce(nullif(_category, ''), 'other'),
    _link, _related_patient_id, _related_entity_id, coalesce(_metadata, '{}'::jsonb)
  )
  returning id into new_id;

  return new_id;
end;
$$;

create or replace function public.get_workflow_notifications(_limit integer default 100)
returns table (
  id uuid,
  recipient_role text,
  recipient_user_id uuid,
  title text,
  message text,
  severity text,
  category text,
  link text,
  related_patient_id uuid,
  related_entity_id uuid,
  metadata jsonb,
  is_read boolean,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  lim integer := least(greatest(coalesce(_limit, 50), 1), 500);
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  return query
  select n.id, n.recipient_role::text, n.recipient_user_id, n.title, n.message,
         n.severity::text, n.category::text, n.link, n.related_patient_id,
         n.related_entity_id, n.metadata, n.is_read, n.created_at
  from public.notifications n
  where n.recipient_user_id = auth.uid()
     or (n.recipient_role is not null and has_role(auth.uid(), n.recipient_role::app_role))
  order by n.created_at desc
  limit lim;
end;
$$;

grant execute on function public.search_patient_directory(text, integer) to authenticated;
grant execute on function public.get_patient_directory_record(uuid) to authenticated;
grant execute on function public.create_workflow_notification(text, uuid, text, text, text, text, text, uuid, uuid, jsonb) to authenticated;
grant execute on function public.get_workflow_notifications(integer) to authenticated;
