
-- Reconcile production encounter lifecycle hardening.
-- Production migration version: 20260925115745

insert into public.permissions (permission_key, description, is_active)
values (
  'encounters_amend',
  'Harmony Health Hub permission to amend finalized encounter documents',
  true
)
on conflict (permission_key) do update
set description = excluded.description,
    is_active = true,
    updated_at = now();

insert into public.role_permissions (role, permission_key)
values
  ('admin'::public.app_role, 'encounters_amend'),
  ('it_admin'::public.app_role, 'encounters_amend')
on conflict (role, permission_key) do nothing;

alter table public.prescriptions
  add column if not exists diagnosis_id uuid;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.prescriptions'::regclass
      and conname = 'prescriptions_diagnosis_id_fkey'
  ) then
    alter table public.prescriptions
      add constraint prescriptions_diagnosis_id_fkey
      foreign key (diagnosis_id) references public.diagnoses(id);
  end if;
end
$$;

create index if not exists idx_prescriptions_diagnosis_id
  on public.prescriptions(diagnosis_id);

create or replace function public.create_encounter_prescription(
  _encounter_id uuid, _medication text, _dosage text default null,
  _frequency text default null, _duration text default null,
  _diagnosis_id uuid default null
)
returns public.prescriptions
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare uid uuid := auth.uid(); result public.prescriptions; v_encounter public.encounters%rowtype;
begin
  if uid is null then raise exception 'Authentication required'; end if;
  if not (public.has_role(uid,'admin') or public.has_role(uid,'practitioner')
    or public.has_role(uid,'nurse') or public.has_role(uid,'midwife')
    or public.has_role(uid,'specialist_nurse')) then
    raise exception 'Not authorized to prescribe';
  end if;
  select * into v_encounter from public.encounters where id=_encounter_id for update;
  if v_encounter.id is null then raise exception 'Encounter does not exist'; end if;
  if v_encounter.status in ('completed','cancelled') then
    raise exception 'Completed or cancelled encounters are read-only';
  end if;
  if nullif(pg_catalog.btrim(_medication),'') is null then raise exception 'Medication is required'; end if;
  if _diagnosis_id is null then raise exception 'Select the diagnosis being treated before prescribing'; end if;
  if not exists (select 1 from public.diagnoses d where d.id=_diagnosis_id and d.encounter_id=_encounter_id) then
    raise exception 'Selected treatment diagnosis does not belong to this encounter';
  end if;
  insert into public.prescriptions(encounter_id,patient_id,prescribed_by,medication,dosage,frequency,duration,diagnosis_id)
  values(v_encounter.id,v_encounter.patient_id,uid,pg_catalog.btrim(_medication),
    nullif(pg_catalog.btrim(_dosage),''),nullif(pg_catalog.btrim(_frequency),''),
    nullif(pg_catalog.btrim(_duration),''),_diagnosis_id)
  returning * into result;
  return result;
end;
$function$;

revoke execute on function public.create_encounter_prescription(uuid,text,text,text,text) from public, anon, authenticated;
revoke execute on function public.create_encounter_prescription(uuid,text,text,text,text,uuid) from public, anon, authenticated;
grant execute on function public.create_encounter_prescription(uuid,text,text,text,text,uuid) to authenticated;

create or replace function public.submit_encounter_workflow(
  _encounter_id uuid, _specialty text default null,
  _appointment_date timestamptz default null, _referral_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_enc public.encounters%rowtype; v_referral uuid; v_snapshot jsonb; v_version integer;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into v_enc from public.encounters where id=_encounter_id for update;
  if v_enc.id is null then raise exception 'Encounter not found'; end if;
  if v_enc.practitioner_id <> auth.uid() and not public.has_role(auth.uid(),'admin') then
    raise exception 'Only the encounter creator can submit this document';
  end if;
  if v_enc.status='completed' then raise exception 'Encounter is already submitted'; end if;
  if not exists (select 1 from public.diagnoses d where d.encounter_id=v_enc.id and d.is_principal=true) then
    raise exception 'Principal diagnosis required before final submission';
  end if;
  if nullif(pg_catalog.btrim(v_enc.treatment_plan),'') is null
     and exists (select 1 from public.prescriptions p where p.encounter_id=v_enc.id) then
    raise exception 'Treatment plan is required when prescriptions are documented';
  end if;
  if nullif(pg_catalog.btrim(_specialty),'') is not null then
    if _appointment_date is null then raise exception 'Referral appointment date is required'; end if;
    insert into public.patient_referrals(
      patient_id,encounter_id,referred_by,destination,specialty,reason,urgency,status,clinical_summary,appointment_date
    ) values(
      v_enc.patient_id,v_enc.id,auth.uid(),'Specialist Clinic',pg_catalog.btrim(_specialty),
      coalesce(nullif(pg_catalog.btrim(_referral_reason),''),'Specialist review requested'),
      'routine','requested',coalesce(v_enc.treatment_plan,v_enc.principal_diagnosis),_appointment_date
    ) returning id into v_referral;
  end if;
  v_version:=greatest(coalesce(v_enc.version_no,1),1);
  v_snapshot:=jsonb_build_object(
    'encounter',to_jsonb(v_enc),
    'diagnoses',coalesce((select jsonb_agg(to_jsonb(d) order by d.created_at,d.id) from public.diagnoses d where d.encounter_id=v_enc.id),'[]'::jsonb),
    'prescriptions',coalesce((select jsonb_agg(to_jsonb(p) order by p.created_at,p.id) from public.prescriptions p where p.encounter_id=v_enc.id),'[]'::jsonb),
    'referral_id',v_referral
  );
  update public.encounters set status='completed',submitted_at=now(),submitted_by=auth.uid(),locked_at=now(),version_no=v_version,updated_at=now()
  where id=_encounter_id;
  insert into public.document_versions(entity_type,entity_id,version_no,action,snapshot,changed_by)
  values('encounter',v_enc.id,v_version,'submitted',v_snapshot,auth.uid())
  on conflict(entity_type,entity_id,version_no) do nothing;
  perform public.record_system_audit('encounter_submitted','clinical','encounter',v_enc.id,'info',
    jsonb_build_object('patient_id',v_enc.patient_id,'version_no',v_version,'referral_id',v_referral));
  return jsonb_build_object('encounter_id',v_enc.id,'status','completed','version_no',v_version,'referral_id',v_referral);
end;
$function$;

revoke execute on function public.submit_encounter_workflow(uuid,text,timestamptz,text) from public, anon, authenticated;
grant execute on function public.submit_encounter_workflow(uuid,text,timestamptz,text) to authenticated;

create or replace function public.amend_encounter_workflow(
  _encounter_id uuid, _symptoms text default null, _clerking_notes text default null,
  _principal_diagnosis text default null, _treatment_plan text default null,
  _reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  uid uuid:=auth.uid(); v_enc public.encounters%rowtype; v_snapshot jsonb;
  v_next_version integer; v_has_permission boolean:=false;
begin
  if uid is null then raise exception 'Authentication required'; end if;
  select * into v_enc from public.encounters where id=_encounter_id for update;
  if v_enc.id is null then raise exception 'Encounter not found'; end if;
  select exists(
    select 1 from public.user_roles ur
    join public.role_permissions rp on rp.role=ur.role
    join public.permissions p on p.permission_key=rp.permission_key
    where ur.user_id=uid and p.permission_key='encounters_amend' and p.is_active=true
  ) into v_has_permission;
  if v_enc.practitioner_id<>uid and not public.has_role(uid,'admin')
     and not public.has_role(uid,'it_admin') and not v_has_permission then
    raise exception 'You are not authorized to amend this encounter';
  end if;
  if v_enc.status<>'completed' then raise exception 'Only finalized encounters can be amended'; end if;
  if nullif(pg_catalog.btrim(_reason),'') is null then raise exception 'Amendment reason is required'; end if;
  v_next_version:=greatest(coalesce(v_enc.version_no,1),1)+1;
  v_snapshot:=jsonb_build_object(
    'encounter',to_jsonb(v_enc),
    'diagnoses',coalesce((select jsonb_agg(to_jsonb(d) order by d.created_at,d.id) from public.diagnoses d where d.encounter_id=v_enc.id),'[]'::jsonb),
    'prescriptions',coalesce((select jsonb_agg(to_jsonb(p) order by p.created_at,p.id) from public.prescriptions p where p.encounter_id=v_enc.id),'[]'::jsonb),
    'amendment_reason',pg_catalog.btrim(_reason)
  );
  insert into public.document_versions(entity_type,entity_id,version_no,action,snapshot,changed_by)
  values('encounter',v_enc.id,v_next_version,'amendment',v_snapshot,uid);
  update public.encounters set
    symptoms=nullif(pg_catalog.btrim(_symptoms),''), clerking_notes=nullif(pg_catalog.btrim(_clerking_notes),''),
    principal_diagnosis=nullif(pg_catalog.btrim(_principal_diagnosis),''), treatment_plan=nullif(pg_catalog.btrim(_treatment_plan),''),
    version_no=v_next_version, updated_at=now()
  where id=v_enc.id;
  perform public.record_system_audit('encounter_amended','clinical','encounter',v_enc.id,'warning',
    jsonb_build_object('patient_id',v_enc.patient_id,'previous_version',greatest(coalesce(v_enc.version_no,1),1),
      'new_version',v_next_version,'reason',pg_catalog.btrim(_reason),'amended_by',uid));
  return jsonb_build_object('encounter_id',v_enc.id,'status','completed','version_no',v_next_version,'amended_by',uid);
end;
$function$;

revoke execute on function public.amend_encounter_workflow(uuid,text,text,text,text,text) from public, anon, authenticated;
grant execute on function public.amend_encounter_workflow(uuid,text,text,text,text,text) to authenticated;

create or replace function public.admit_encounter_workflow(
  _encounter_id uuid, _reason text default null, _ward text default null, _emergency_override boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_enc public.encounters%rowtype; v_admission uuid; v_override boolean:=false;
  v_order record; v_ward_name text; uid uuid:=auth.uid();
begin
  if uid is null then raise exception 'Authentication required'; end if;
  if not (public.has_role(uid,'admin') or public.has_role(uid,'practitioner') or public.has_role(uid,'nurse')
    or public.has_role(uid,'midwife') or public.has_role(uid,'specialist_nurse')) then
    raise exception 'Admission is not permitted for this role';
  end if;
  select * into v_enc from public.encounters where id=_encounter_id for update;
  if not found then raise exception 'Encounter not found'; end if;
  if not exists(select 1 from public.patients where id=v_enc.patient_id) then raise exception 'Encounter patient not found'; end if;
  if v_enc.status='cancelled' then raise exception 'Cancelled encounters cannot be admitted'; end if;
  if v_enc.admission_id is not null then
    return jsonb_build_object('admission_id',v_enc.admission_id,'override',false,'existing',true);
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_enc.patient_id::text,0));
  if exists(select 1 from public.admissions where patient_id=v_enc.patient_id and status='admitted') then
    raise exception 'Patient already has an active admission';
  end if;
  if nullif(pg_catalog.btrim(_ward),'') is not null then
    select wu.name into v_ward_name from public.ward_units wu
    where wu.active=true and (lower(pg_catalog.btrim(wu.name))=lower(pg_catalog.btrim(_ward)) or lower(pg_catalog.btrim(wu.code))=lower(pg_catalog.btrim(_ward)))
    order by wu.name limit 1;
    if v_ward_name is null then raise exception 'Active ward not found'; end if;
  end if;
  select coalesce(allow_treatment_before_deposit,false) and coalesce(admission_financial_override_enabled,false)
    and coalesce(allow_clinical_emergency_override,false) into v_override
  from public.facility_configuration where id='default' limit 1;
  v_override:=coalesce(v_override,false) and coalesce(_emergency_override,true);
  insert into public.admissions(patient_id,encounter_id,ward,reason,admitted_by,status)
  values(v_enc.patient_id,v_enc.id,v_ward_name,coalesce(nullif(pg_catalog.btrim(_reason),''),'Clinical admission'),uid,'admitted')
  returning id into v_admission;
  update public.encounters set admission_id=v_admission,updated_at=now() where id=v_enc.id;
  if v_override then
    for v_order in select * from public.service_orders where encounter_id=v_enc.id and status='pending_payment_approval' for update loop
      insert into public.billing_overrides(service_order_id,patient_id,department,related_entity_id,reason,overridden_by,approved_by,approved_at)
      values(v_order.id,v_order.patient_id,v_order.department,v_order.related_entity_id,
        coalesce(nullif(pg_catalog.btrim(_reason),''),'Emergency treatment before deposit'),uid,uid,now())
      on conflict(service_order_id) do update set reason=excluded.reason,overridden_by=excluded.overridden_by,approved_by=excluded.approved_by,approved_at=excluded.approved_at;
      update public.service_orders set status='released',approved_at=now(),approved_by=uid,released_at=now(),released_by=uid,
        release_reason='Emergency admission financial override',notes=concat_ws(E'\n',notes,'Emergency admission financial override: treatment released before deposit.'),updated_at=now()
      where id=v_order.id;
      insert into public.department_queues(service_order_id,patient_id,department,related_encounter_id,related_invoice_id,payment_required,payment_satisfied,priority,reason,created_by,queued_at,status)
      values(v_order.id,v_order.patient_id,v_order.department,v_order.encounter_id,v_order.invoice_id,v_order.payment_required,true,'normal',v_order.service_name,uid,now(),'queued')
      on conflict(service_order_id) do update set payment_satisfied=true,status=case when public.department_queues.status='cancelled' then 'queued' else public.department_queues.status end,updated_at=now();
    end loop;
    perform public.record_system_audit('admission_financial_override','admissions','admission',v_admission,'critical',
      jsonb_build_object('encounter_id',v_enc.id,'patient_id',v_enc.patient_id,'override',true));
  end if;
  perform public.record_system_audit('patient_admitted','admissions','admission',v_admission,'info',
    jsonb_build_object('encounter_id',v_enc.id,'patient_id',v_enc.patient_id,'financial_override',v_override));
  insert into public.notifications(recipient_role,title,message,severity,category,link,related_patient_id,related_entity_id,metadata)
  values
    ('nurse'::public.app_role,'New inpatient admission','A patient has been admitted from a clinical encounter and requires inpatient handover',
      case when v_override then 'critical' else 'high' end,'admission','/inpatient',v_enc.patient_id,v_admission,
      jsonb_build_object('encounter_id',v_enc.id,'admission_id',v_admission,'requires_acknowledgement',true)),
    ('specialist_nurse'::public.app_role,'New inpatient admission','A patient has been admitted from a clinical encounter and requires inpatient handover',
      case when v_override then 'critical' else 'high' end,'admission','/inpatient',v_enc.patient_id,v_admission,
      jsonb_build_object('encounter_id',v_enc.id,'admission_id',v_admission,'requires_acknowledgement',true)),
    ('midwife'::public.app_role,'New inpatient admission','A patient has been admitted from a clinical encounter and requires inpatient handover',
      case when v_override then 'critical' else 'high' end,'admission','/inpatient',v_enc.patient_id,v_admission,
      jsonb_build_object('encounter_id',v_enc.id,'admission_id',v_admission,'requires_acknowledgement',true));
  return jsonb_build_object('admission_id',v_admission,'override',v_override,'status','admitted');
end;
$function$;

revoke execute on function public.admit_encounter_workflow(uuid,text,text,boolean) from public, anon, authenticated;
grant execute on function public.admit_encounter_workflow(uuid,text,text,boolean) to authenticated;
