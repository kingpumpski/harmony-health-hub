alter table public.facility_configuration
  add column if not exists require_principal_diagnosis_for_final boolean not null default true,
  add column if not exists inherit_inpatient_diagnoses boolean not null default true,
  add column if not exists notification_sound_enabled boolean not null default true;

update public.facility_configuration
set require_principal_diagnosis_for_final = coalesce(require_principal_diagnosis_for_final,true),
    inherit_inpatient_diagnoses = coalesce(inherit_inpatient_diagnoses,true),
    notification_sound_enabled = coalesce(notification_sound_enabled,true);

create or replace function public.update_facility_configuration_workflow(_configuration_id uuid, _changes jsonb)
returns public.facility_configuration
language plpgsql
security definer
set search_path to 'pg_catalog','public'
as $function$
declare
  uid uuid := auth.uid();
  v_config public.facility_configuration;
begin
  if uid is null then raise exception 'Authentication required'; end if;
  if not public.has_role(uid,'admin'::public.app_role) then
    raise exception 'Administrator role required to update facility configuration';
  end if;
  if _changes is null or jsonb_typeof(_changes) <> 'object' then
    raise exception 'Configuration changes must be a JSON object';
  end if;
  select * into v_config from public.facility_configuration where id=_configuration_id for update;
  if not found then raise exception 'Facility configuration not found'; end if;

  update public.facility_configuration
  set
    facility_name = case when _changes ? 'facility_name' then nullif(pg_catalog.btrim(_changes->>'facility_name'),'') else facility_name end,
    facility_code = case when _changes ? 'facility_code' then nullif(pg_catalog.btrim(_changes->>'facility_code'),'') else facility_code end,
    phone = case when _changes ? 'phone' then nullif(pg_catalog.btrim(_changes->>'phone'),'') else phone end,
    email = case when _changes ? 'email' then nullif(pg_catalog.btrim(_changes->>'email'),'') else email end,
    address = case when _changes ? 'address' then nullif(pg_catalog.btrim(_changes->>'address'),'') else address end,
    country = case when _changes ? 'country' then nullif(pg_catalog.btrim(_changes->>'country'),'') else country end,
    currency = case when _changes ? 'currency' then nullif(pg_catalog.btrim(_changes->>'currency'),'') else currency end,
    timezone = case when _changes ? 'timezone' then nullif(pg_catalog.btrim(_changes->>'timezone'),'') else timezone end,
    routing_mode = case when _changes ? 'routing_mode' then _changes->>'routing_mode' else routing_mode end,
    appointment_buffer_minutes = case when _changes ? 'appointment_buffer_minutes' then greatest(0,(_changes->>'appointment_buffer_minutes')::integer) else appointment_buffer_minutes end,
    maintenance_mode = case when _changes ? 'maintenance_mode' then (_changes->>'maintenance_mode')::boolean else maintenance_mode end,
    allow_treatment_before_deposit = case when _changes ? 'allow_treatment_before_deposit' then (_changes->>'allow_treatment_before_deposit')::boolean else allow_treatment_before_deposit end,
    admission_financial_override_enabled = case when _changes ? 'admission_financial_override_enabled' then (_changes->>'admission_financial_override_enabled')::boolean else admission_financial_override_enabled end,
    require_accounts_release_after_deposit = case when _changes ? 'require_accounts_release_after_deposit' then (_changes->>'require_accounts_release_after_deposit')::boolean else require_accounts_release_after_deposit end,
    allow_clinical_emergency_override = case when _changes ? 'allow_clinical_emergency_override' then (_changes->>'allow_clinical_emergency_override')::boolean else allow_clinical_emergency_override end,
    require_principal_diagnosis_for_final = case when _changes ? 'require_principal_diagnosis_for_final' then (_changes->>'require_principal_diagnosis_for_final')::boolean else require_principal_diagnosis_for_final end,
    inherit_inpatient_diagnoses = case when _changes ? 'inherit_inpatient_diagnoses' then (_changes->>'inherit_inpatient_diagnoses')::boolean else inherit_inpatient_diagnoses end,
    notification_sound_enabled = case when _changes ? 'notification_sound_enabled' then (_changes->>'notification_sound_enabled')::boolean else notification_sound_enabled end,
    updated_by=uid, updated_at=now()
  where id=_configuration_id
  returning * into v_config;

  if v_config.routing_mode not in ('pay_before_each_step','streamlined') then
    raise exception 'Invalid facility routing mode';
  end if;

  perform public.record_system_audit(
    'facility_configuration_updated','administration','facility_configuration',v_config.id,'info',
    jsonb_build_object('updated_by',uid,'changed_fields',(select jsonb_agg(key) from jsonb_object_keys(_changes) as key))
  );
  return v_config;
end;
$function$;

create or replace function public.create_encounter_workflow(
  _patient_id uuid,
  _symptoms text default null,
  _clerking_notes text default null
)
returns public.encounters
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  result public.encounters;
  uid uuid := auth.uid();
  v_admission_id uuid;
  v_initial_encounter_id uuid;
  v_inherit boolean := true;
begin
  if uid is null then raise exception 'Authentication required'; end if;
  if not (
    public.has_role(uid,'admin'::public.app_role)
    or public.has_role(uid,'practitioner'::public.app_role)
    or public.has_role(uid,'nurse'::public.app_role)
    or public.has_role(uid,'midwife'::public.app_role)
    or public.has_role(uid,'specialist_nurse'::public.app_role)
  ) then
    raise exception 'Only authorized clinical staff may create encounters';
  end if;
  if not exists(select 1 from public.patients where id=_patient_id) then raise exception 'Patient does not exist'; end if;

  select a.id, cfg.inherit_inpatient_diagnoses
    into v_admission_id, v_inherit
  from public.admissions a
  cross join lateral (
    select coalesce(fc.inherit_inpatient_diagnoses,true) as inherit_inpatient_diagnoses
    from public.facility_configuration fc
    order by fc.created_at asc
    limit 1
  ) cfg
  where a.patient_id=_patient_id and a.status='admitted'
  order by a.admitted_at asc nulls first, a.created_at asc
  limit 1;

  insert into public.encounters(patient_id,symptoms,clerking_notes,practitioner_id,status,admission_id)
  values(_patient_id,nullif(trim(_symptoms),''),nullif(trim(_clerking_notes),''),uid,'draft',v_admission_id)
  returning * into result;

  if v_admission_id is not null and v_inherit then
    select e.id into v_initial_encounter_id
    from public.encounters e
    where e.admission_id=v_admission_id and e.id<>result.id
    order by e.created_at asc,e.id asc
    limit 1;

    if v_initial_encounter_id is not null then
      insert into public.diagnoses(encounter_id,diagnosis,is_principal,icd_code,ai_suggested)
      select result.id,d.diagnosis,d.is_principal,d.icd_code,d.ai_suggested
      from public.diagnoses d
      where d.encounter_id=v_initial_encounter_id;

      select d.diagnosis into result.principal_diagnosis
      from public.diagnoses d
      where d.encounter_id=result.id and d.is_principal=true
      order by d.created_at asc,d.id asc
      limit 1;

      update public.encounters
      set principal_diagnosis=result.principal_diagnosis,updated_at=now()
      where id=result.id
      returning * into result;

      perform public.record_system_audit(
        'encounter_diagnoses_inherited','clinical','encounter',result.id,'info',
        jsonb_build_object('patient_id',result.patient_id,'admission_id',v_admission_id,'source_encounter_id',v_initial_encounter_id)
      );
    end if;
  end if;
  return result;
end;
$function$;

create or replace function public.submit_encounter_workflow(
  _encounter_id uuid,
  _specialty text default null,
  _appointment_date timestamptz default null,
  _referral_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public'
as $function$
declare
  v_enc public.encounters%rowtype;
  v_referral uuid;
  v_snapshot jsonb;
  v_version integer;
  v_require_principal boolean := true;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into v_enc from public.encounters where id=_encounter_id for update;
  if v_enc.id is null then raise exception 'Encounter not found'; end if;
  if v_enc.practitioner_id<>auth.uid() and not public.has_role(auth.uid(),'admin') then raise exception 'Only the encounter creator can submit this document'; end if;
  if v_enc.status='completed' then raise exception 'Encounter is already submitted'; end if;

  select coalesce(require_principal_diagnosis_for_final,true) into v_require_principal
  from public.facility_configuration order by created_at asc limit 1;

  if v_require_principal and not exists(select 1 from public.diagnoses d where d.encounter_id=v_enc.id and d.is_principal=true) then
    raise exception 'Principal diagnosis required before final submission';
  end if;

  if nullif(pg_catalog.btrim(v_enc.treatment_plan),'') is null
     and exists(select 1 from public.prescriptions p where p.encounter_id=v_enc.id) then
    raise exception 'Treatment plan is required when prescriptions are documented';
  end if;

  if nullif(pg_catalog.btrim(_specialty),'') is not null then
    if _appointment_date is null then raise exception 'Referral appointment date is required'; end if;
    insert into public.patient_referrals(patient_id,encounter_id,referred_by,destination,specialty,reason,urgency,status,clinical_summary,appointment_date)
    values(v_enc.patient_id,v_enc.id,auth.uid(),'Specialist Clinic',pg_catalog.btrim(_specialty),
      coalesce(nullif(pg_catalog.btrim(_referral_reason),''),'Specialist review requested'),
      'routine','requested',coalesce(v_enc.treatment_plan,v_enc.principal_diagnosis),_appointment_date)
    returning id into v_referral;
  end if;

  v_version:=greatest(coalesce(v_enc.version_no,1),1);
  v_snapshot:=jsonb_build_object(
    'encounter',to_jsonb(v_enc),
    'diagnoses',coalesce((select jsonb_agg(to_jsonb(d) order by d.created_at,d.id) from public.diagnoses d where d.encounter_id=v_enc.id),'[]'::jsonb),
    'prescriptions',coalesce((select jsonb_agg(to_jsonb(p) order by p.created_at,p.id) from public.prescriptions p where p.encounter_id=v_enc.id),'[]'::jsonb),
    'referral_id',v_referral,
    'workflow_requirements',jsonb_build_object('require_principal_diagnosis',v_require_principal)
  );

  update public.encounters set status='completed',submitted_at=now(),submitted_by=auth.uid(),locked_at=now(),version_no=v_version,updated_at=now() where id=_encounter_id;
  insert into public.document_versions(entity_type,entity_id,version_no,action,snapshot,changed_by)
  values('encounter',v_enc.id,v_version,'submitted',v_snapshot,auth.uid())
  on conflict(entity_type,entity_id,version_no) do nothing;

  perform public.record_system_audit('encounter_submitted','clinical','encounter',v_enc.id,'info',
    jsonb_build_object('patient_id',v_enc.patient_id,'version_no',v_version,'referral_id',v_referral,'require_principal_diagnosis',v_require_principal));

  return jsonb_build_object('encounter_id',v_enc.id,'status','completed','version_no',v_version,'referral_id',v_referral,'require_principal_diagnosis',v_require_principal);
end;
$function$;

revoke execute on function public.update_facility_configuration_workflow(uuid,jsonb) from public,anon;
grant execute on function public.update_facility_configuration_workflow(uuid,jsonb) to authenticated;
revoke execute on function public.create_encounter_workflow(uuid,text,text) from public,anon;
grant execute on function public.create_encounter_workflow(uuid,text,text) to authenticated;
revoke execute on function public.submit_encounter_workflow(uuid,text,timestamptz,text) from public,anon;
grant execute on function public.submit_encounter_workflow(uuid,text,timestamptz,text) to authenticated;
