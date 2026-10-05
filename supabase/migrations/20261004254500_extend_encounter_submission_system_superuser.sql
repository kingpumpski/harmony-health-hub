-- Extend encounter submission administration to the canonical System Superuser role.
-- Facility boundaries remain mandatory for every caller.

create or replace function public.submit_encounter_workflow(
  _encounter_id uuid,
  _specialty text default null,
  _appointment_date timestamptz default null,
  _referral_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_enc public.encounters%rowtype;
  v_referral uuid;
  v_snapshot jsonb;
  v_version integer;
  v_require_principal boolean := true;
  v_patient_facility uuid;
  v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'Authentication required'; end if;

  select * into v_enc from public.encounters where id = _encounter_id for update;
  if v_enc.id is null then raise exception 'Encounter not found'; end if;

  perform public.ensure_encounter_facility_attribution(_encounter_id);
  select * into v_enc from public.encounters where id = _encounter_id for update;

  v_patient_facility := public.assert_patient_facility_context(v_enc.patient_id);
  if v_enc.facility_id is null then raise exception 'Encounter facility attribution is unresolved'; end if;
  if v_enc.facility_id is distinct from v_patient_facility then
    raise exception 'Encounter or patient belongs to a different facility context';
  end if;

  if v_enc.practitioner_id <> v_uid
     and not public.has_role(v_uid,'admin')
     and not public.has_role(v_uid,'it_admin')
     and not public.has_role(v_uid,'system_superuser') then
    raise exception 'Only the encounter creator can submit this document';
  end if;

  if v_enc.status = 'completed' then raise exception 'Encounter is already submitted'; end if;

  select coalesce(require_principal_diagnosis_for_final,true)
    into v_require_principal
  from public.facility_configuration
  order by created_at asc
  limit 1;

  if v_require_principal and not exists (
    select 1 from public.diagnoses d
    where d.encounter_id = v_enc.id and d.is_principal = true
  ) then
    raise exception 'Principal diagnosis required before final submission';
  end if;

  if nullif(pg_catalog.btrim(v_enc.treatment_plan),'') is null
     and exists(select 1 from public.prescriptions p where p.encounter_id = v_enc.id) then
    raise exception 'Treatment plan is required when prescriptions are documented';
  end if;

  if nullif(pg_catalog.btrim(_specialty),'') is not null then
    if _appointment_date is null then raise exception 'Referral appointment date is required'; end if;
    insert into public.patient_referrals(
      patient_id,encounter_id,referred_by,destination,specialty,reason,urgency,status,
      clinical_summary,appointment_date,facility_id
    )
    values(
      v_enc.patient_id,v_enc.id,v_uid,'Specialist Clinic',pg_catalog.btrim(_specialty),
      coalesce(nullif(pg_catalog.btrim(_referral_reason),''),'Specialist review requested'),
      'routine','requested',coalesce(v_enc.treatment_plan,v_enc.principal_diagnosis),
      _appointment_date,v_patient_facility
    )
    returning id into v_referral;
  end if;

  v_version := greatest(coalesce(v_enc.version_no,1),1);
  v_snapshot := jsonb_build_object(
    'encounter',to_jsonb(v_enc),
    'diagnoses',coalesce((select jsonb_agg(to_jsonb(d) order by d.created_at,d.id) from public.diagnoses d where d.encounter_id=v_enc.id),'[]'::jsonb),
    'prescriptions',coalesce((select jsonb_agg(to_jsonb(p) order by p.created_at,p.id) from public.prescriptions p where p.encounter_id=v_enc.id),'[]'::jsonb),
    'referral_id',v_referral,
    'workflow_requirements',jsonb_build_object('require_principal_diagnosis',v_require_principal)
  );

  update public.encounters
  set status='completed',submitted_at=pg_catalog.now(),submitted_by=v_uid,locked_at=pg_catalog.now(),
      version_no=v_version,updated_at=pg_catalog.now()
  where id=_encounter_id;

  insert into public.document_versions(entity_type,entity_id,version_no,action,snapshot,changed_by)
  values('encounter',v_enc.id,v_version,'submitted',v_snapshot,v_uid)
  on conflict(entity_type,entity_id,version_no,action) do nothing;

  perform public.record_system_audit(
    'encounter_submitted','clinical','encounter',v_enc.id,'info',
    jsonb_build_object('patient_id',v_enc.patient_id,'version_no',v_version,'referral_id',v_referral,
      'require_principal_diagnosis',v_require_principal)
  );

  return jsonb_build_object('encounter_id',v_enc.id,'status','completed','version_no',v_version,
    'referral_id',v_referral,'require_principal_diagnosis',v_require_principal);
end;
$function$;

revoke all on function public.submit_encounter_workflow(uuid,text,timestamptz,text) from public, anon;
grant execute on function public.submit_encounter_workflow(uuid,text,timestamptz,text) to authenticated;

notify pgrst, 'reload schema';
