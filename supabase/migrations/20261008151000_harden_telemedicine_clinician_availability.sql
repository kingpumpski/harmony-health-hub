-- Final telemedicine clinician availability boundary.
-- Availability is evaluated at the requested time against the facility and active shift roster.

drop function if exists public.get_patient_telemedicine_clinicians();

create or replace function public.get_patient_telemedicine_clinicians(_scheduled_at timestamptz default null)
returns table(id uuid,first_name text,last_name text,department text,specialization text,clinician_role text)
language plpgsql stable security definer set search_path=''
as $$
declare uid uuid:=auth.uid(); v_facility uuid; v_at timestamptz:=coalesce(_scheduled_at,now()+interval '1 day');
begin
  if uid is null or not public.has_role(uid,'patient') then raise exception 'Patient telemedicine access is not permitted'; end if;
  if v_at <= now() then raise exception 'Choose a future date and time'; end if;
  select p.facility_id into v_facility from public.patients p
  where (p.user_id=uid or (p.user_id is null and lower(p.email)=lower(auth.jwt()->>'email')))
    and coalesce(p.status,'active') <> 'inactive'
  order by (p.user_id=uid) desc,p.created_at desc limit 1;
  if v_facility is null then raise exception 'Patient facility is not configured'; end if;
  return query
  select p.id,p.first_name,p.last_name,p.department,p.specialization,ur.role::text
  from public.profiles p
  join public.user_roles ur on ur.user_id=p.id
  join public.facility_memberships fm on fm.user_id=p.id and fm.is_active=true and fm.facility_id=v_facility
  where ur.role in ('practitioner'::public.app_role,'radiologist'::public.app_role)
    and exists (select 1 from public.staff_shift_assignments s where s.user_id=p.id and s.active=true and s.starts_at<=v_at and s.ends_at>v_at)
  group by p.id,p.first_name,p.last_name,p.department,p.specialization,ur.role
  order by p.last_name,p.first_name;
end;
$$;

revoke all on function public.get_patient_telemedicine_clinicians(timestamptz) from public,anon;
grant execute on function public.get_patient_telemedicine_clinicians(timestamptz) to authenticated;
