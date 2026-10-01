create or replace function public.get_appointment_clinicians()
returns table(id uuid, first_name text, last_name text, department text, specialization text, clinician_role text)
language plpgsql stable security definer set search_path = ''
as $function$
declare
  v_user uuid := auth.uid();
  v_facility uuid := public.current_user_facility_id();
  v_test boolean := public.hms_current_user_is_test_user();
  v_cross_facility boolean := public.has_role(v_user,'admin'::public.app_role)
    or public.has_role(v_user,'it_admin'::public.app_role)
    or public.current_user_has_role('system_superuser');
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if not (
    public.has_role(v_user,'admin'::public.app_role)
    or public.has_role(v_user,'it_admin'::public.app_role)
    or public.has_role(v_user,'system_superuser'::public.app_role)
    or public.has_role(v_user,'practitioner'::public.app_role)
    or public.has_role(v_user,'nurse'::public.app_role)
    or public.has_role(v_user,'midwife'::public.app_role)
    or public.has_role(v_user,'specialist_nurse'::public.app_role)
    or public.has_role(v_user,'front_desk'::public.app_role)
  ) then raise exception 'Appointment clinician directory access denied'; end if;
  if not v_cross_facility and not v_test and v_facility is null then
    raise exception 'An active facility is required to access the clinician directory';
  end if;

  return query
  select distinct
    p.id,p.first_name,p.last_name,p.department,p.specialization,ur.role::text
  from public.profiles p
  join public.user_roles ur on ur.user_id=p.id
  left join public.facility_memberships fm on fm.user_id=p.id and fm.is_active=true
  where ur.role in ('practitioner'::public.app_role,'radiologist'::public.app_role)
    and (
      v_cross_facility
      or (v_test and exists (
        select 1 from public.hms_test_users tu
        where tu.user_id=p.id and tu.enabled=true
      ))
      or fm.facility_id=v_facility
    )
  order by p.last_name,p.first_name;
end;
$function$;

create or replace function public.get_appointment_worklist(_limit integer default 300)
returns table(
  id uuid, patient_id uuid, patient_code text, patient_first_name text, patient_last_name text,
  scheduled_at timestamptz, consultation_type text, practitioner_id uuid, practitioner_name text,
  department text, reason text, status text, attending_officer_id uuid, treatment_status text,
  treatment_notes text
)
language plpgsql stable security definer set search_path = ''
as $function$
declare
  v_limit integer := greatest(1, least(coalesce(_limit,300),500));
  v_user uuid := auth.uid();
  v_facility uuid := public.current_user_facility_id();
  v_test boolean := public.hms_current_user_is_test_user();
  v_cross_facility boolean := public.has_role(v_user,'admin'::public.app_role)
    or public.has_role(v_user,'it_admin'::public.app_role)
    or public.current_user_has_role('system_superuser');
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if not (
    public.has_role(v_user,'admin'::public.app_role)
    or public.has_role(v_user,'it_admin'::public.app_role)
    or public.has_role(v_user,'system_superuser'::public.app_role)
    or public.has_role(v_user,'practitioner'::public.app_role)
    or public.has_role(v_user,'nurse'::public.app_role)
    or public.has_role(v_user,'midwife'::public.app_role)
    or public.has_role(v_user,'specialist_nurse'::public.app_role)
    or public.has_role(v_user,'front_desk'::public.app_role)
  ) then raise exception 'Appointment worklist access denied'; end if;
  if not v_cross_facility and not v_test and v_facility is null then
    raise exception 'An active facility is required to access the appointment worklist';
  end if;

  return query
  select
    a.id,a.patient_id,p.patient_code,p.first_name,p.last_name,a.scheduled_at,
    coalesce(a.consultation_type,'General Consultation'),a.practitioner_id,
    nullif(pg_catalog.btrim(pg_catalog.concat_ws(' ',pr.first_name,pr.last_name)),''),
    a.department,a.reason,a.status,a.attending_officer_id,a.treatment_status,a.treatment_notes
  from public.appointments a
  join public.patients p on p.id=a.patient_id
  left join public.profiles pr on pr.id=a.practitioner_id
  where coalesce(p.status,'active') <> 'inactive'
    and (
      v_cross_facility
      or (
        v_test
        and (
          (a.facility_id is null and p.facility_id is null)
          or (a.facility_id=v_facility and p.facility_id=v_facility)
        )
      )
      or (a.facility_id=v_facility and p.facility_id=v_facility)
    )
  order by a.scheduled_at asc
  limit v_limit;
end;
$function$;

revoke all on function public.get_appointment_clinicians() from public, anon;
grant execute on function public.get_appointment_clinicians() to authenticated;
revoke all on function public.get_appointment_worklist(integer) from public, anon;
grant execute on function public.get_appointment_worklist(integer) to authenticated;
