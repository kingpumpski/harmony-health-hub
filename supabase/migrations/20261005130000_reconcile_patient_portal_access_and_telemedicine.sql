-- Patient portal access reconciliation: own appointments/invoices/telemedicine only.
-- Staff worklists remain separate and must never be broadened for patient users.

create or replace function public.get_patient_portal_identity()
returns table(
  id uuid, patient_code text, first_name text, last_name text, email text,
  date_of_birth date, phone text, facility_id uuid
)
language plpgsql stable security definer
set search_path = ''
as $$
declare v_uid uuid := auth.uid(); v_email text := lower(nullif(trim((auth.jwt() ->> 'email')), ''));
begin
  if v_uid is null then raise exception 'Authentication required'; end if;
  return query
  select p.id,p.patient_code,p.first_name,p.last_name,p.email,p.date_of_birth,p.phone,p.facility_id
  from public.patients p
  where (p.user_id = v_uid or (p.user_id is null and v_email is not null and lower(p.email)=v_email))
    and coalesce(p.status,'active') <> 'inactive'
  order by (p.user_id = v_uid) desc, p.created_at desc
  limit 1;
end;
$$;

create or replace function public.get_patient_appointments(_patient_id uuid default null,_limit integer default 100)
returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_limit integer := greatest(1,least(coalesce(_limit,100),100));
  v_patient uuid;
  v_staff boolean;
begin
  if v_uid is null then raise exception 'Authentication required'; end if;
  v_staff := public.has_role(v_uid,'admin') or public.has_role(v_uid,'system_superuser')
    or public.has_role(v_uid,'it_admin') or public.has_role(v_uid,'practitioner')
    or public.has_role(v_uid,'nurse') or public.has_role(v_uid,'midwife')
    or public.has_role(v_uid,'specialist_nurse') or public.has_role(v_uid,'radiologist')
    or public.has_role(v_uid,'radiology_technician') or public.has_role(v_uid,'front_desk');
  if v_staff then
    if _patient_id is null then raise exception 'Patient is required'; end if;
    perform public.assert_patient_facility_read_context(_patient_id);
    v_patient := _patient_id;
  else
    select p.id into v_patient from public.patients p
    where p.id = coalesce(_patient_id,p.id)
      and (p.user_id=v_uid or (p.user_id is null and lower(p.email)=lower((auth.jwt()->>'email'))))
      and coalesce(p.status,'active') <> 'inactive'
    limit 1;
    if v_patient is null then raise exception 'Patient appointment access is not permitted'; end if;
  end if;
  return coalesce((select jsonb_agg(to_jsonb(x) order by x.scheduled_at desc) from (
    select a.id,a.patient_id,a.scheduled_at,a.reason,a.status,a.department,a.attending_officer_id,a.treatment_status,a.treatment_notes
    from public.appointments a where a.patient_id=v_patient order by a.scheduled_at desc limit v_limit
  ) x),'[]'::jsonb);
end;
$$;

create or replace function public.get_patient_invoice_summary(_limit integer default 100)
returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
declare v_uid uuid := auth.uid(); v_patient uuid; v_limit integer := greatest(1,least(coalesce(_limit,100),100));
begin
  if v_uid is null then raise exception 'Authentication required'; end if;
  select p.id into v_patient from public.patients p
  where p.user_id=v_uid or (p.user_id is null and lower(p.email)=lower((auth.jwt()->>'email')))
  order by (p.user_id=v_uid) desc,p.created_at desc limit 1;
  if v_patient is null then raise exception 'Patient billing profile not found'; end if;
  return coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from (
    select i.id,i.invoice_number,i.created_at,i.total_amount,i.paid_amount,i.outstanding_amount,i.status,i.notes
    from public.invoices i where i.patient_id=v_patient order by i.created_at desc limit v_limit
  ) x),'[]'::jsonb);
end;
$$;

create or replace function public.get_patient_telemedicine_clinicians()
returns table(id uuid,first_name text,last_name text,department text,specialization text,clinician_role text)
language plpgsql stable security definer
set search_path = ''
as $$
declare v_uid uuid:=auth.uid(); v_facility uuid;
begin
  if v_uid is null then raise exception 'Authentication required'; end if;
  if not public.has_role(v_uid,'patient') then raise exception 'Patient telemedicine access is not permitted'; end if;
  select p.facility_id into v_facility from public.patients p
  where p.user_id=v_uid or (p.user_id is null and lower(p.email)=lower((auth.jwt()->>'email')))
  order by (p.user_id=v_uid) desc,p.created_at desc limit 1;
  if v_facility is null then raise exception 'Patient facility is not configured'; end if;
  return query
  select distinct p.id,p.first_name,p.last_name,p.department,p.specialization,ur.role::text
  from public.profiles p join public.user_roles ur on ur.user_id=p.id
  join public.facility_memberships fm on fm.user_id=p.id and fm.is_active=true
  where ur.role in ('practitioner'::public.app_role,'radiologist'::public.app_role)
    and fm.facility_id=v_facility
  order by p.last_name,p.first_name;
end;
$$;

create or replace function public.request_patient_telemedicine_session(
  _clinician_id uuid,_scheduled_at timestamptz,_reason text
)
returns uuid
language plpgsql security definer
set search_path = ''
as $$
declare v_uid uuid:=auth.uid(); v_patient uuid; v_facility uuid; v_id uuid;
begin
  if v_uid is null or not public.has_role(v_uid,'patient') then raise exception 'Patient telemedicine access is not permitted'; end if;
  select p.id,p.facility_id into v_patient,v_facility from public.patients p
  where p.user_id=v_uid or (p.user_id is null and lower(p.email)=lower((auth.jwt()->>'email')))
  order by (p.user_id=v_uid) desc,p.created_at desc limit 1;
  if v_patient is null or v_facility is null then raise exception 'Patient profile or facility is not configured'; end if;
  if _scheduled_at is null or _scheduled_at <= now() then raise exception 'Choose a future date and time'; end if;
  if not exists (
    select 1 from public.profiles p join public.user_roles ur on ur.user_id=p.id
    join public.facility_memberships fm on fm.user_id=p.id and fm.is_active=true
    where p.id=_clinician_id and ur.role in ('practitioner'::public.app_role,'radiologist'::public.app_role)
      and fm.facility_id=v_facility
  ) then raise exception 'Selected clinician is not available at this facility'; end if;
  insert into public.video_sessions(patient_id,practitioner_id,room_name,provider,scheduled_at,status,payment_required,payment_received,notes,facility_id)
  values(v_patient,_clinician_id,'pending-'||replace(gen_random_uuid()::text,'-',''),'jitsi',_scheduled_at,'pending_approval',false,false,nullif(trim(_reason),''),
    v_facility) returning id into v_id;
  return v_id;
end;
$$;

drop policy if exists "patient own appointments select" on public.appointments;
create policy "patient own appointments select" on public.appointments for select to authenticated
using (exists (
  select 1 from public.patients p where p.id=appointments.patient_id
  and (p.user_id=(select auth.uid()) or (p.user_id is null and lower(p.email)=lower((select auth.jwt()->>'email'))))
));

drop policy if exists "patient own invoices select" on public.invoices;
create policy "patient own invoices select" on public.invoices for select to authenticated
using (exists (
  select 1 from public.patients p where p.id=invoices.patient_id
  and (p.user_id=(select auth.uid()) or (p.user_id is null and lower(p.email)=lower((select auth.jwt()->>'email'))))
));

drop policy if exists "patient own video sessions select" on public.video_sessions;
create policy "patient own video sessions select" on public.video_sessions for select to authenticated
using (exists (
  select 1 from public.patients p where p.id=video_sessions.patient_id
  and (p.user_id=(select auth.uid()) or (p.user_id is null and lower(p.email)=lower((select auth.jwt()->>'email'))))
));

revoke all on function public.get_patient_portal_identity() from public,anon;
revoke all on function public.get_patient_appointments(uuid,integer) from public,anon;
revoke all on function public.get_patient_invoice_summary(integer) from public,anon;
revoke all on function public.get_patient_telemedicine_clinicians() from public,anon;
revoke all on function public.request_patient_telemedicine_session(uuid,timestamptz,text) from public,anon;
grant execute on function public.get_patient_portal_identity() to authenticated;
grant execute on function public.get_patient_appointments(uuid,integer) to authenticated;
grant execute on function public.get_patient_invoice_summary(integer) to authenticated;
grant execute on function public.get_patient_telemedicine_clinicians() to authenticated;
grant execute on function public.request_patient_telemedicine_session(uuid,timestamptz,text) to authenticated;
