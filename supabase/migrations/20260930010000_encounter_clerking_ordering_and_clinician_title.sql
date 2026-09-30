-- Encounter clinical document continuity, scoped downstream ordering, and clinician identity title.
-- Draft clerking writes to the canonical encounter row; diagnostic/service orders remain
-- encounter-bound and are created by the attending clinical actor only.

alter table public.profiles
  add column if not exists title text;

comment on column public.profiles.title is
  'Optional professional or honorific title displayed with clinician identity; never used for authorization.';

create or replace function public.save_encounter_clerking(
  _encounter_id uuid,
  _chief_complaint text default null,
  _symptoms text default null,
  _history_of_present_illness text default null,
  _clerking_notes text default null,
  _assessment text default null,
  _plan text default null,
  _treatment_plan text default null,
  _follow_up_date date default null
) returns public.encounters
language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare
  uid uuid := auth.uid();
  v public.encounters;
begin
  if uid is null then raise exception 'Authentication required'; end if;
  select * into v from public.encounters where id = _encounter_id for update;
  if not found then raise exception 'Encounter not found'; end if;
  if v.practitioner_id <> uid and not public.has_role(uid,'admin'::public.app_role) then
    raise exception 'Only the encounter creator or an administrator may save this clerking sheet';
  end if;
  if v.status <> 'draft' then raise exception 'Only draft encounters can be edited'; end if;

  update public.encounters
  set chief_complaint = nullif(pg_catalog.btrim(_chief_complaint),''),
      symptoms = nullif(pg_catalog.btrim(_symptoms),''),
      history_of_present_illness = nullif(pg_catalog.btrim(_history_of_present_illness),''),
      clerking_notes = nullif(pg_catalog.btrim(_clerking_notes),''),
      assessment = nullif(pg_catalog.btrim(_assessment),''),
      plan = nullif(pg_catalog.btrim(_plan),''),
      treatment_plan = nullif(pg_catalog.btrim(_treatment_plan),''),
      follow_up_date = _follow_up_date,
      updated_at = now()
  where id = _encounter_id
  returning * into v;

  return v;
end;
$$;

revoke all on function public.save_encounter_clerking(uuid,text,text,text,text,text,text,text,date) from public, anon;
grant execute on function public.save_encounter_clerking(uuid,text,text,text,text,text,text,text,date) to authenticated;

create or replace function public.create_encounter_lab_order(
  _encounter_id uuid,
  _test_code text,
  _priority text default 'routine',
  _clinical_notes text default null
) returns jsonb
language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare
  uid uuid := auth.uid();
  e public.encounters;
  c public.lab_test_catalogue;
begin
  if uid is null then raise exception 'Authentication required'; end if;
  if not (public.has_role(uid,'admin') or public.has_role(uid,'practitioner') or public.has_role(uid,'nurse')
    or public.has_role(uid,'midwife') or public.has_role(uid,'specialist_nurse')) then
    raise exception 'Clinical encounter ordering access required';
  end if;

  select * into e from public.encounters where id=_encounter_id for update;
  if not found then raise exception 'Encounter not found'; end if;
  if e.status in ('completed','cancelled') then raise exception 'Completed or cancelled encounters are read-only'; end if;
  if e.practitioner_id <> uid and not public.has_role(uid,'admin') then
    raise exception 'Only the encounter clinician or an administrator may order from this encounter';
  end if;

  select * into c
  from public.lab_test_catalogue
  where active=true
    and (lower(test_code)=lower(pg_catalog.btrim(_test_code))
      or lower(test_name)=lower(pg_catalog.btrim(_test_code)))
  order by case when lower(test_code)=lower(pg_catalog.btrim(_test_code)) then 0 else 1 end, created_at desc
  limit 1;

  if not found then raise exception 'Select an active laboratory test from the catalogue'; end if;

  return public.create_lab_order_with_payment_gate(
    e.patient_id, c.test_name, c.category,
    coalesce(nullif(pg_catalog.btrim(_priority),''),'routine'),
    _clinical_notes, coalesce(c.default_charge,0), e.id
  );
end;
$$;

revoke all on function public.create_encounter_lab_order(uuid,text,text,text) from public, anon;
grant execute on function public.create_encounter_lab_order(uuid,text,text,text) to authenticated;

create or replace function public.create_encounter_imaging_order(
  _encounter_id uuid,
  _modality text,
  _study_name text,
  _body_site text default null,
  _priority text default 'routine',
  _clinical_indication text default null
) returns jsonb
language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare
  uid uuid := auth.uid();
  e public.encounters;
  v_tariff public.service_tariffs;
  v_amount numeric := 0;
begin
  if uid is null then raise exception 'Authentication required'; end if;
  if not (public.has_role(uid,'admin') or public.has_role(uid,'practitioner') or public.has_role(uid,'nurse')
    or public.has_role(uid,'midwife') or public.has_role(uid,'specialist_nurse')) then
    raise exception 'Clinical encounter ordering access required';
  end if;

  select * into e from public.encounters where id=_encounter_id for update;
  if not found then raise exception 'Encounter not found'; end if;
  if e.status in ('completed','cancelled') then raise exception 'Completed or cancelled encounters are read-only'; end if;
  if e.practitioner_id <> uid and not public.has_role(uid,'admin') then
    raise exception 'Only the encounter clinician or an administrator may order from this encounter';
  end if;
  if nullif(pg_catalog.btrim(_study_name),'') is null then raise exception 'Imaging study is required'; end if;

  select * into v_tariff
  from public.service_tariffs
  where active=true and lower(department)='imaging'
    and (lower(service_code)=lower(pg_catalog.btrim(_modality))
      or lower(service_name)=lower(pg_catalog.btrim(_study_name)))
  order by case when lower(service_code)=lower(pg_catalog.btrim(_modality)) then 0 else 1 end, created_at desc
  limit 1;

  if found then v_amount := coalesce(v_tariff.amount,0); end if;

  return public.create_imaging_order_with_payment_gate(
    e.patient_id,e.id,coalesce(nullif(pg_catalog.btrim(_modality),''),'X-Ray'),
    pg_catalog.btrim(_study_name),_body_site,
    coalesce(nullif(pg_catalog.btrim(_priority),''),'routine'),
    _clinical_indication,v_amount
  );
end;
$$;

revoke all on function public.create_encounter_imaging_order(uuid,text,text,text,text,text) from public, anon;
grant execute on function public.create_encounter_imaging_order(uuid,text,text,text,text,text) to authenticated;

create or replace function public.create_encounter_service_order(
  _encounter_id uuid,
  _service_code text,
  _notes text default null
) returns jsonb
language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare
  uid uuid := auth.uid();
  e public.encounters;
  t public.service_tariffs;
begin
  if uid is null then raise exception 'Authentication required'; end if;
  if not (public.has_role(uid,'admin') or public.has_role(uid,'practitioner') or public.has_role(uid,'nurse')
    or public.has_role(uid,'midwife') or public.has_role(uid,'specialist_nurse')) then
    raise exception 'Clinical encounter ordering access required';
  end if;

  select * into e from public.encounters where id=_encounter_id for update;
  if not found then raise exception 'Encounter not found'; end if;
  if e.status in ('completed','cancelled') then raise exception 'Completed or cancelled encounters are read-only'; end if;
  if e.practitioner_id <> uid and not public.has_role(uid,'admin') then
    raise exception 'Only the encounter clinician or an administrator may order from this encounter';
  end if;

  select * into t
  from public.service_tariffs
  where active=true
    and (lower(service_code)=lower(pg_catalog.btrim(_service_code))
      or lower(service_name)=lower(pg_catalog.btrim(_service_code)))
  order by case when lower(service_code)=lower(pg_catalog.btrim(_service_code)) then 0 else 1 end, created_at desc
  limit 1;

  if not found then raise exception 'Select an active service from the service tariff catalogue'; end if;

  return public.create_service_order(
    e.patient_id,e.id,t.department,t.service_name,coalesce(t.amount,0),
    null,_notes,uid,null,null,'service',t.service_code
  );
end;
$$;

revoke all on function public.create_encounter_service_order(uuid,text,text) from public, anon;
grant execute on function public.create_encounter_service_order(uuid,text,text) to authenticated;
