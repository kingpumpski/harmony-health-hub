-- Telemedicine clinician availability accepts a requested time while retaining the
-- same patient/facility privacy boundary. Shift integration can refine availability
-- later without changing the patient request contract.
drop function if exists public.get_patient_telemedicine_clinicians();

create or replace function public.get_patient_telemedicine_clinicians(_scheduled_at timestamptz default now())
returns table(id uuid,first_name text,last_name text,department text,specialization text,clinician_role text)
language plpgsql stable security definer
set search_path=''
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
  from public.profiles p
  join public.user_roles ur on ur.user_id=p.id
  join public.facility_memberships fm on fm.user_id=p.id and fm.is_active=true
  where ur.role in ('practitioner'::public.app_role,'radiologist'::public.app_role)
    and fm.facility_id=v_facility
    and (_scheduled_at is null or _scheduled_at > now())
  order by p.last_name,p.first_name;
end;
$$;

revoke all on function public.get_patient_telemedicine_clinicians(timestamptz) from public,anon;
grant execute on function public.get_patient_telemedicine_clinicians(timestamptz) to authenticated;
