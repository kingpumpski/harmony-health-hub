-- Extend facility reconciliation inventory/control plane to specialty,
-- inpatient, nursing, referral, insurance, pharmacy, procedure, transfusion,
-- emergency and AI clinical records.
create or replace function public.list_unresolved_clinical_facility_records(_limit integer default 100)
returns table(entity_type text,entity_id uuid,patient_id uuid,created_at timestamptz,metadata jsonb)
language plpgsql security definer set search_path='' as $$declare r record;begin
if not(public.has_role(auth.uid(),'admin') or public.has_role(auth.uid(),'it_admin')) then raise exception 'Only administrators can inspect unresolved facility records';end if;
for r in select * from (
select 'emergency_cases' t,id,patient_id,created_at,jsonb_build_object('status',status,'triage_priority',triage_priority) m from public.emergency_cases where facility_id is null
union all select 'maternity_episodes',id,patient_id,created_at,jsonb_build_object('status',status,'risk_level',risk_level) from public.maternity_episodes where facility_id is null
union all select 'fertility_cycles',id,patient_id,created_at,jsonb_build_object('cycle_type',cycle_type,'status',status) from public.fertility_cycles where facility_id is null
union all select 'inpatient_bed_movements',id,patient_id,moved_at,jsonb_build_object('movement_type',movement_type,'admission_id',admission_id) from public.inpatient_bed_movements where facility_id is null
union all select 'nursing_care_plans',id,patient_id,created_at,jsonb_build_object('problem',problem,'status',status) from public.nursing_care_plans where facility_id is null
union all select 'nursing_shift_handovers',id,patient_id,created_at,jsonb_build_object('shift_name',shift_name,'escalation_required',escalation_required) from public.nursing_shift_handovers where facility_id is null
union all select 'patient_referrals',id,patient_id,created_at,jsonb_build_object('destination',destination,'specialty',specialty,'status',status) from public.patient_referrals where facility_id is null
union all select 'care_transitions',id,patient_id,created_at,jsonb_build_object('transition_type',transition_type,'status',status) from public.care_transitions where facility_id is null
union all select 'insurance_cases',id,patient_id,created_at,jsonb_build_object('payer_name',payer_name,'claim_status',claim_status) from public.insurance_cases where facility_id is null
union all select 'insurance_claims',id,patient_id,created_at,jsonb_build_object('claim_number',claim_number,'status',status) from public.insurance_claims where facility_id is null
union all select 'pharmacy_dispensing_plans',id,patient_id,created_at,jsonb_build_object('medication_name',medication_name,'status',status) from public.pharmacy_dispensing_plans where facility_id is null
union all select 'pharmacy_pos_sales',id,patient_id,created_at,jsonb_build_object('medication',medication,'status',status) from public.pharmacy_pos_sales where facility_id is null
union all select 'procedure_notes',id,patient_id,created_at,jsonb_build_object('procedure_name',procedure_name,'status',status) from public.procedure_notes where facility_id is null
union all select 'theatre_cases',id,patient_id,created_at,jsonb_build_object('procedure_name',procedure_name,'status',status) from public.theatre_cases where facility_id is null
union all select 'transfusion_records',id,patient_id,created_at,jsonb_build_object('component',component,'status',status) from public.transfusion_records where facility_id is null
union all select 'vital_alerts',id,patient_id,created_at,jsonb_build_object('alert_type',alert_type,'severity',severity) from public.vital_alerts where facility_id is null
union all select 'ai_case_memory',id,patient_id,created_at,jsonb_build_object('diagnosis',diagnosis,'encounter_id',encounter_id) from public.ai_case_memory where facility_id is null
union all select 'ai_clinical_sessions',id,patient_id,created_at,jsonb_build_object('specialist',specialist,'status',status) from public.ai_clinical_sessions where facility_id is null
union all select 'ai_report_requests',id,patient_id,created_at,jsonb_build_object('report_type',report_type,'status',status) from public.ai_report_requests where facility_id is null
union all select 'nursing_notes',id,patient_id,created_at,jsonb_build_object('note_type',note_type,'admission_id',admission_id) from public.nursing_notes where facility_id is null
) q order by created_at nulls last limit greatest(1,least(coalesce(_limit,100),500))
loop entity_type:=r.t;entity_id:=r.id;patient_id:=r.patient_id;created_at:=r.created_at;metadata:=r.m;return next;end loop;end$$;
revoke all on function public.list_unresolved_clinical_facility_records(integer) from public,anon;grant execute on function public.list_unresolved_clinical_facility_records(integer) to authenticated;

create or replace function public.reconcile_extended_clinical_facility_record(_entity_type text,_entity_id uuid,_target_facility_id uuid,_reason text)
returns jsonb language plpgsql security definer set search_path='' as $$declare v_actor uuid:=auth.uid();v_source uuid;v_parent uuid;v_patient uuid;v_exists boolean:=false;begin
if v_actor is null or not(public.has_role(v_actor,'admin') or public.has_role(v_actor,'it_admin')) then raise exception 'Only administrators can reconcile clinical facility attribution';end if;
if _target_facility_id is null or nullif(btrim(_reason),'') is null then raise exception 'Target facility and reconciliation reason are required';end if;
if not exists(select 1 from public.healthcare_facilities f where f.id=_target_facility_id and f.is_active) then raise exception 'Target facility is not active';end if;
if _entity_type not in ('emergency_cases','maternity_episodes','fertility_cycles','inpatient_bed_movements','nursing_care_plans','nursing_shift_handovers','patient_referrals','care_transitions','insurance_cases','insurance_claims','pharmacy_dispensing_plans','pharmacy_pos_sales','procedure_notes','theatre_cases','transfusion_records','vital_alerts','ai_case_memory','ai_clinical_sessions','ai_report_requests','nursing_notes','ai_diagnosis_suggestions','ward_beds') then raise exception 'Unsupported extended clinical entity type';end if;
perform set_config('hms.facility_reconciliation','on',true);
if _entity_type='ai_diagnosis_suggestions' then select e.facility_id into v_source from public.encounters e where e.id=(select encounter_id from public.ai_diagnosis_suggestions where id=_entity_id);v_exists:=found;
else execute format('select facility_id,patient_id,true from public.%I where id=$1',_entity_type) into v_source,v_patient,v_exists using _entity_id;end if;
if not v_exists then raise exception 'Clinical record not found';end if;
if v_patient is not null then select p.facility_id into v_parent from public.patients p where p.id=v_patient;if v_parent is null then raise exception 'Reconcile the parent patient facility first';elsif v_parent<>_target_facility_id then raise exception 'Target facility conflicts with patient facility';end if;end if;
if _entity_type='insurance_claims' then select i.facility_id into v_parent from public.invoices i where i.id=(select invoice_id from public.insurance_claims where id=_entity_id);if v_parent is not null and v_parent<>_target_facility_id then raise exception 'Target facility conflicts with invoice facility';end if;end if;
execute format('update public.%I set facility_id=$1 where id=$2 and facility_id is null',_entity_type) using _target_facility_id,_entity_id;
insert into public.clinical_facility_reconciliation(entity_type,entity_id,source_facility_id,target_facility_id,reason,reviewed_by,metadata) values(_entity_type,_entity_id,v_source,_target_facility_id,btrim(_reason),v_actor,jsonb_build_object('entity_type',_entity_type,'entity_id',_entity_id)) on conflict(entity_type,entity_id) do update set source_facility_id=excluded.source_facility_id,target_facility_id=excluded.target_facility_id,status='corrected',reason=excluded.reason,reviewed_by=excluded.reviewed_by,reviewed_at=now(),metadata=excluded.metadata;
perform public.record_system_audit('clinical_facility_reconciled','facility_control_plane',_entity_type,_entity_id,'warning',jsonb_build_object('source_facility_id',v_source,'target_facility_id',_target_facility_id,'reason',btrim(_reason),'actor_id',v_actor));
return jsonb_build_object('ok',true,'entity_type',_entity_type,'entity_id',_entity_id,'target_facility_id',_target_facility_id);end$$;
revoke all on function public.reconcile_extended_clinical_facility_record(text,uuid,uuid,text) from public,anon;grant execute on function public.reconcile_extended_clinical_facility_record(text,uuid,uuid,text) to authenticated;