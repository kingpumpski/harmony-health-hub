-- Harden patient telemedicine requests to use the same time-specific clinician availability boundary
-- exposed by get_patient_telemedicine_clinicians().
-- Patient requests remain request-only and cannot start/end clinical sessions.

begin;

create or replace function public.request_patient_telemedicine_session(
  _clinician_id uuid,
  _scheduled_at timestamptz,
  _reason text
)
returns uuid
language plpgsql
security definer
set search_path=''
as $$
declare
  v_uid uuid := auth.uid();
  v_patient uuid;
  v_facility uuid;
  v_id uuid;
  v_lock_key bigint;
begin
  if v_uid is null or not public.has_role(v_uid,'patient'::public.app_role) then
    raise exception 'Patient telemedicine access is not permitted' using errcode='42501';
  end if;

  select p.id,p.facility_id into v_patient,v_facility
  from public.patients p
  where (p.user_id=v_uid or (p.user_id is null and lower(p.email)=lower((auth.jwt()->>'email'))))
    and coalesce(p.status,'active') <> 'inactive'
  order by (p.user_id=v_uid) desc,p.created_at desc
  limit 1;

  if v_patient is null or v_facility is null then
    raise exception 'Patient profile or facility is not configured' using errcode='42501';
  end if;

  if _clinician_id is null or _scheduled_at is null or _scheduled_at <= now() then
    raise exception 'Choose a future date, time and clinician' using errcode='22023';
  end if;

  if nullif(pg_catalog.btrim(coalesce(_reason,'')),'') is null then
    raise exception 'Reason for the telemedicine visit is required' using errcode='22023';
  end if;

  if not exists (
    select 1
    from public.profiles p
    join public.user_roles ur on ur.user_id=p.id
    join public.facility_memberships fm
      on fm.user_id=p.id
     and fm.is_active=true
     and fm.facility_id=v_facility
    where p.id=_clinician_id
      and ur.role in ('practitioner'::public.app_role,'radiologist'::public.app_role)
      and exists (
        select 1
        from public.staff_shift_assignments s
        where s.user_id=p.id
          and s.active=true
          and s.starts_at<=_scheduled_at
          and s.ends_at>_scheduled_at
      )
  ) then
    raise exception 'Selected clinician is not on duty at the requested time' using errcode='42501';
  end if;

  v_lock_key := hashtextextended(
    v_patient::text || '|' || _scheduled_at::text || '|' || _clinician_id::text, 0
  );
  perform pg_advisory_xact_lock(v_lock_key);

  if exists (
    select 1
    from public.video_sessions s
    where s.patient_id=v_patient
      and s.scheduled_at=_scheduled_at
      and coalesce(s.status,'pending') not in ('cancelled','completed','declined')
  ) then
    raise exception 'A telemedicine request already exists for this patient and time' using errcode='23505';
  end if;

  if exists (
    select 1
    from public.video_sessions s
    where s.practitioner_id=_clinician_id
      and s.scheduled_at=_scheduled_at
      and coalesce(s.status,'pending') not in ('cancelled','completed','declined')
  ) then
    raise exception 'The selected clinician is already booked at that time' using errcode='23505';
  end if;

  insert into public.video_sessions(
    patient_id,practitioner_id,room_name,provider,scheduled_at,status,
    payment_required,payment_received,notes,facility_id
  )
  values(
    v_patient,_clinician_id,
    'pending-'||replace(gen_random_uuid()::text,'-',''),
    'jitsi',_scheduled_at,'pending_approval',
    false,false,pg_catalog.nullif(pg_catalog.btrim(_reason),''),
    v_facility
  )
  returning id into v_id;

  return v_id;
end;
$$;

revoke all on function public.request_patient_telemedicine_session(uuid,timestamptz,text) from public,anon;
grant execute on function public.request_patient_telemedicine_session(uuid,timestamptz,text) to authenticated;

notify pgrst,'reload schema';
commit;
