-- Patient portal self-service runtime reconciliation.
-- Patients may view only their own published/confirmed medical information and their own
-- portal services. These APIs do not grant access to clinical workflow mutations.

create or replace function public.get_patient_portal_video_sessions(_limit integer default 50)
returns jsonb
language plpgsql stable security definer set search_path=''
as $$
declare uid uuid:=auth.uid(); v_patient uuid; lim integer:=greatest(1,least(coalesce(_limit,50),100));
begin
  if uid is null then raise exception 'Authentication required'; end if;
  select p.id into v_patient from public.patients p
  where (p.user_id=uid or (p.user_id is null and lower(p.email)=lower(auth.jwt()->>'email')))
    and coalesce(p.status,'active') <> 'inactive'
  order by (p.user_id=uid) desc,p.created_at desc limit 1;
  if v_patient is null then raise exception 'Patient portal profile not found'; end if;
  return coalesce((select jsonb_agg(to_jsonb(x) order by x.scheduled_at desc) from (
    select id,patient_id,practitioner_id,scheduled_at,status,payment_received,room_name,notes
    from public.video_sessions where patient_id=v_patient
    order by scheduled_at desc limit lim
  ) x),'[]'::jsonb);
end;
$$;

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

create or replace function public.create_patient_appointment(
  _patient_id uuid,_scheduled_at timestamptz,_department text default null,_reason text default null
)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare uid uuid:=auth.uid(); pf uuid; v_id uuid; own boolean;
begin
  if uid is null then raise exception 'Authentication required'; end if;
  own:=exists(select 1 from public.patients p where p.id=_patient_id and coalesce(p.status,'active')<>'inactive'
    and (p.user_id=uid or (p.user_id is null and lower(p.email)=lower(auth.jwt()->>'email'))));
  if not public.has_role(uid,'patient') or not own then raise exception 'You may only request appointments for your own patient record'; end if;
  pf:=public.assert_patient_facility_context(_patient_id);
  if _scheduled_at is null or _scheduled_at <= now() then raise exception 'A future appointment time is required'; end if;
  insert into public.appointments(patient_id,practitioner_id,department,scheduled_at,duration_minutes,reason,status,created_at,updated_at,treatment_status,facility_id)
  values(_patient_id,null,nullif(pg_catalog.btrim(coalesce(_department,'')),''),_scheduled_at,30,nullif(pg_catalog.btrim(coalesce(_reason,'')),''),'scheduled',now(),now(),'scheduled',pf)
  returning id into v_id;
  insert into public.notifications(recipient_role,recipient_user_id,title,message,severity,category,link,related_patient_id,related_entity_id,metadata)
  values('patient'::public.app_role,uid,'Appointment request submitted',
    concat('Your appointment request for ',to_char(_scheduled_at,'DD Mon YYYY HH24:MI'),' has been submitted for facility review.'),
    'info','appointment','/appointments',_patient_id,v_id,jsonb_build_object('appointment_id',v_id,'requested_at',_scheduled_at));
  return jsonb_build_object('appointment_id',v_id,'facility_id',pf,'status','scheduled');
end;
$$;

create or replace function public.get_patient_portal_meal_menus(_service_date date)
returns jsonb
language plpgsql stable security definer set search_path=''
as $$
declare uid uuid:=auth.uid(); v_patient uuid; v_facility uuid;
begin
  if uid is null or not public.has_role(uid,'patient') then raise exception 'Patient meal menu access is not permitted'; end if;
  select p.id,p.facility_id into v_patient,v_facility from public.patients p
  where (p.user_id=uid or (p.user_id is null and lower(p.email)=lower(auth.jwt()->>'email')))
    and coalesce(p.status,'active') <> 'inactive'
  order by (p.user_id=uid) desc,p.created_at desc limit 1;
  if v_patient is null then raise exception 'Patient portal profile not found'; end if;
  if not exists(select 1 from public.admissions a where a.patient_id=v_patient and a.facility_id=v_facility
    and a.discharged_at is null and coalesce(a.status,'active') not in ('discharged','cancelled')) then
    raise exception 'Meal menus are available to admitted patients only';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
    'id',m.id,'service_date',m.service_date,'meal_period',m.meal_period,'available_from',m.available_from,
    'available_until',m.available_until,'status',m.status,'notes',m.notes,'items',
      coalesce((select jsonb_agg(jsonb_build_object('name',i.name,'description',i.description,'dietary_tags',i.dietary_tags,'allergens',i.allergens,'ingredients',i.ingredients) order by i.sort_order)
        from public.meal_menu_items i where i.menu_id=m.id and i.active=true),'[]'::jsonb))
    order by m.meal_period)
    from public.meal_menus m where m.service_date=coalesce(_service_date,current_date) and m.status='published'),'[]'::jsonb);
end;
$$;

create or replace function public.get_patient_outside_lab_documents(_limit integer default 50)
returns jsonb
language plpgsql stable security definer set search_path=''
as $$
declare uid uuid:=auth.uid(); v_patient uuid; lim integer:=greatest(1,least(coalesce(_limit,50),100));
begin
  if uid is null or not public.has_role(uid,'patient') then raise exception 'Patient outside diagnostics access is not permitted'; end if;
  select p.id into v_patient from public.patients p
  where (p.user_id=uid or (p.user_id is null and lower(p.email)=lower(auth.jwt()->>'email')))
    and coalesce(p.status,'active') <> 'inactive'
  order by (p.user_id=uid) desc,p.created_at desc limit 1;
  if v_patient is null then raise exception 'Patient portal profile not found'; end if;
  return coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from (
    select id,patient_id,document_type,title,created_at,ai_analysis
    from public.outside_lab_documents where patient_id=v_patient order by created_at desc limit lim
  ) x),'[]'::jsonb);
end;
$$;

revoke all on function public.get_patient_portal_video_sessions(integer) from public,anon;
revoke all on function public.get_patient_telemedicine_clinicians(timestamptz) from public,anon;
revoke all on function public.create_patient_appointment(uuid,timestamptz,text,text) from public,anon;
revoke all on function public.get_patient_portal_meal_menus(date) from public,anon;
revoke all on function public.get_patient_outside_lab_documents(integer) from public,anon;
grant execute on function public.get_patient_portal_video_sessions(integer) to authenticated;
grant execute on function public.get_patient_telemedicine_clinicians(timestamptz) to authenticated;
grant execute on function public.create_patient_appointment(uuid,timestamptz,text,text) to authenticated;
grant execute on function public.get_patient_portal_meal_menus(date) to authenticated;
grant execute on function public.get_patient_outside_lab_documents(integer) to authenticated;

notify pgrst,'reload schema';
