-- Reconcile patient appointment requests with the canonical concurrency boundary.
-- Patient self-service remains request-only: it never grants clinical lifecycle mutation authority.

create or replace function public.create_patient_appointment(
  _patient_id uuid,
  _scheduled_at timestamptz,
  _department text default null,
  _reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  uid uuid := auth.uid();
  pf uuid;
  v_id uuid;
  v_key bigint;
begin
  if uid is null then
    raise exception 'Authentication required' using errcode='42501';
  end if;
  if not public.has_role(uid,'patient'::public.app_role) then
    raise exception 'Patient appointment self-service is required' using errcode='42501';
  end if;
  if not exists (
    select 1 from public.patients p
    where p.id=_patient_id
      and coalesce(p.status,'active') <> 'inactive'
      and (p.user_id=uid or (p.user_id is null and lower(p.email)=lower(auth.jwt()->>'email')))
  ) then
    raise exception 'You may only request appointments for your own patient record' using errcode='42501';
  end if;

  pf := public.assert_patient_facility_context(_patient_id);
  if _scheduled_at is null or _scheduled_at <= now() then
    raise exception 'A future appointment time is required' using errcode='22023';
  end if;
  if nullif(pg_catalog.btrim(coalesce(_department,'')),'') is null then
    raise exception 'Department is required' using errcode='22023';
  end if;

  v_key := hashtextextended(_patient_id::text || '|' || _scheduled_at::text, 0);
  perform pg_advisory_xact_lock(v_key);

  if exists (
    select 1 from public.appointments a
    where a.patient_id=_patient_id
      and a.scheduled_at=_scheduled_at
      and coalesce(a.treatment_status,'scheduled') not in ('cancelled','no_show','completed')
  ) then
    raise exception 'An active appointment already exists for this patient and time' using errcode='23505';
  end if;

  insert into public.appointments(
    patient_id,practitioner_id,department,scheduled_at,duration_minutes,reason,
    status,created_at,updated_at,treatment_status,facility_id
  )
  values(
    _patient_id,null,pg_catalog.nullif(pg_catalog.btrim(_department),''),
    _scheduled_at,30,pg_catalog.nullif(pg_catalog.btrim(_reason),''),
    'scheduled',now(),now(),'scheduled',pf
  )
  returning id into v_id;

  insert into public.notifications(
    recipient_role,recipient_user_id,title,message,severity,category,link,
    related_patient_id,related_entity_id,metadata
  )
  values(
    'patient'::public.app_role,uid,'Appointment request submitted',
    concat('Your appointment request for ',to_char(_scheduled_at,'DD Mon YYYY HH24:MI'),' has been submitted for facility review.'),
    'info','appointment','/appointments',_patient_id,v_id,
    jsonb_build_object('appointment_id',v_id,'requested_at',_scheduled_at,'facility_id',pf)
  );

  return jsonb_build_object(
    'appointment_id',v_id,
    'facility_id',pf,
    'status','scheduled'
  );
end;
$$;

revoke all on function public.create_patient_appointment(uuid,timestamptz,text,text) from public,anon;
grant execute on function public.create_patient_appointment(uuid,timestamptz,text,text) to authenticated;
