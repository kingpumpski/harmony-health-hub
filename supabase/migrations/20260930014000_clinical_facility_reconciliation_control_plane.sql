-- Governed reconciliation of legacy clinical facility attribution.
-- Historical rows remain unresolved until an administrator or IT administrator records evidence.
create table if not exists public.clinical_facility_reconciliation (
  id uuid primary key default gen_random_uuid(), entity_type text not null, entity_id uuid not null,
  source_facility_id uuid references public.healthcare_facilities(id),
  target_facility_id uuid not null references public.healthcare_facilities(id),
  status text not null default 'reconciled' check (status in ('reconciled','corrected')),
  reason text not null, reviewed_by uuid not null references auth.users(id),
  reviewed_at timestamptz not null default now(), created_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb, unique(entity_type,entity_id)
);
alter table public.clinical_facility_reconciliation enable row level security;
revoke all on public.clinical_facility_reconciliation from public,anon,authenticated;
create policy "clinical facility reconciliation is rpc only" on public.clinical_facility_reconciliation as restrictive for all to authenticated using (false) with check (false);
create index if not exists clinical_facility_reconciliation_target_idx on public.clinical_facility_reconciliation(target_facility_id);

create or replace function public.assign_active_facility() returns trigger
language plpgsql security definer set search_path=''
as $$ declare v_facility uuid; v_reconciliation boolean:=coalesce(current_setting('hms.facility_reconciliation',true),'off')='on';
begin
 v_facility:=public.current_user_facility_id();
 if new.facility_id is null then
   if tg_op='UPDATE' then raise exception 'Facility attribution cannot be cleared'; end if;
   if v_facility is null and not (v_reconciliation and (public.current_user_has_role('admin') or public.current_user_has_role('it_admin'))) then raise exception 'An active facility is required for clinical transaction writes'; end if;
   if v_facility is not null then new.facility_id:=v_facility; end if;
 elsif v_facility is null then
   if not (v_reconciliation and (public.current_user_has_role('admin') or public.current_user_has_role('it_admin'))) then raise exception 'An active facility is required for clinical transaction writes'; end if;
 elsif new.facility_id<>v_facility and not (v_reconciliation and (public.current_user_has_role('admin') or public.current_user_has_role('it_admin'))) then raise exception 'Facility context mismatch'; end if;
 return new; end $$;
revoke all on function public.assign_active_facility() from public,anon,authenticated;

create or replace function public.sync_child_facility_from_parent() returns trigger
language plpgsql security definer set search_path=''
as $$ declare v_facility uuid; v_reconciliation boolean:=coalesce(current_setting('hms.facility_reconciliation',true),'off')='on';
begin
 if tg_table_name='department_queues' then select so.facility_id into v_facility from public.service_orders so where so.id=new.service_order_id;
 elsif tg_table_name='lab_orders' then select e.facility_id into v_facility from public.encounters e where e.id=new.encounter_id; if v_facility is null then select p.facility_id into v_facility from public.patients p where p.id=new.patient_id; end if;
 elsif tg_table_name='lab_results' then select lo.facility_id into v_facility from public.lab_orders lo where lo.id=new.lab_order_id;
 elsif tg_table_name='imaging_orders' then select e.facility_id into v_facility from public.encounters e where e.id=new.encounter_id; if v_facility is null then select p.facility_id into v_facility from public.patients p where p.id=new.patient_id; end if;
 elsif tg_table_name='prescriptions' then select e.facility_id into v_facility from public.encounters e where e.id=new.encounter_id; if v_facility is null then select p.facility_id into v_facility from public.patients p where p.id=new.patient_id; end if;
 elsif tg_table_name='diagnoses' then select e.facility_id into v_facility from public.encounters e where e.id=new.encounter_id; if v_facility is null then select p.facility_id into v_facility from public.patients p where p.id=new.patient_id; end if; end if;
 if v_facility is null then raise exception 'Parent clinical record has no facility attribution'; end if;
 if new.facility_id is null then if tg_op='UPDATE' then raise exception 'Facility attribution cannot be cleared'; end if; new.facility_id:=v_facility;
 elsif new.facility_id<>v_facility and not (v_reconciliation and (public.current_user_has_role('admin') or public.current_user_has_role('it_admin'))) then raise exception 'Facility lineage mismatch'; end if;
 return new; end $$;
revoke all on function public.sync_child_facility_from_parent() from public,anon,authenticated;

create or replace function public.list_unresolved_clinical_facility_records(_limit integer default 100)
returns table(entity_type text,entity_id uuid,patient_id uuid,created_at timestamptz,metadata jsonb)
language sql security definer set search_path=''
as $$ select x.* from (
 select 'patients'::text,p.id,p.id,p.created_at,jsonb_build_object('patient_code',p.patient_code,'first_name',p.first_name,'last_name',p.last_name,'date_of_birth',p.date_of_birth) from public.patients p where p.facility_id is null
 union all select 'encounters',e.id,e.patient_id,e.created_at,jsonb_build_object('encounter_type',e.encounter_type,'status',e.status,'appointment_id',e.appointment_id) from public.encounters e where e.facility_id is null
 union all select 'service_orders',s.id,s.patient_id,s.created_at,jsonb_build_object('department',s.department,'service_name',s.service_name,'status',s.status,'encounter_id',s.encounter_id) from public.service_orders s where s.facility_id is null
 union all select 'department_queues',q.id,q.patient_id,q.created_at,jsonb_build_object('department',q.department,'status',q.status,'service_order_id',q.service_order_id) from public.department_queues q where q.facility_id is null
 union all select 'lab_orders',l.id,l.patient_id,l.created_at,jsonb_build_object('test_name',l.test_name,'status',l.status,'encounter_id',l.encounter_id) from public.lab_orders l where l.facility_id is null
 union all select 'lab_results',r.id,r.patient_id,r.created_at,jsonb_build_object('lab_order_id',r.lab_order_id,'status',r.status) from public.lab_results r where r.facility_id is null
 union all select 'imaging_orders',i.id,i.patient_id,i.created_at,jsonb_build_object('modality',i.modality,'study_name',i.study_name,'status',i.status,'encounter_id',i.encounter_id) from public.imaging_orders i where i.facility_id is null
 union all select 'prescriptions',rx.id,rx.patient_id,rx.created_at,jsonb_build_object('medication',coalesce(rx.medication_name,rx.medication),'status',rx.status,'encounter_id',rx.encounter_id) from public.prescriptions rx where rx.facility_id is null
 union all select 'diagnoses',d.id,d.patient_id,d.created_at,jsonb_build_object('diagnosis',d.diagnosis,'icd_code',d.icd_code,'encounter_id',d.encounter_id) from public.diagnoses d where d.facility_id is null
) x where public.has_role(auth.uid(),'admin') or public.has_role(auth.uid(),'it_admin') order by x.created_at nulls last limit greatest(1,least(coalesce(_limit,100),500)); $$;
revoke all on function public.list_unresolved_clinical_facility_records(integer) from public,anon;
grant execute on function public.list_unresolved_clinical_facility_records(integer) to authenticated;

create or replace function public.reconcile_clinical_facility_record(_entity_type text,_entity_id uuid,_target_facility_id uuid,_reason text)
returns jsonb language plpgsql security definer set search_path=''
as $$ declare v_actor uuid:=auth.uid(); v_source uuid; v_patient uuid; v_parent uuid; v_ref uuid; v_exists boolean:=false; v_metadata jsonb:='{}'::jsonb;
begin
 if v_actor is null or not(public.has_role(v_actor,'admin') or public.has_role(v_actor,'it_admin')) then raise exception 'Only administrators can reconcile clinical facility attribution'; end if;
 if _target_facility_id is null or nullif(btrim(_reason),'') is null then raise exception 'Target facility and reconciliation reason are required'; end if;
 if not exists(select 1 from public.healthcare_facilities f where f.id=_target_facility_id and f.is_active) then raise exception 'Target facility is not active'; end if;
 perform set_config('hms.facility_reconciliation','on',true);
 if _entity_type='patients' then
  select p.facility_id,p.id,true,jsonb_build_object('patient_code',p.patient_code,'first_name',p.first_name,'last_name',p.last_name) into v_source,v_patient,v_exists,v_metadata from public.patients p where p.id=_entity_id;
  if v_exists then update public.patients set facility_id=_target_facility_id,updated_at=now() where id=_entity_id and facility_id is null; end if;
 elsif _entity_type='encounters' then
  select e.facility_id,e.patient_id,true,jsonb_build_object('encounter_type',e.encounter_type,'status',e.status) into v_source,v_patient,v_exists,v_metadata from public.encounters e where e.id=_entity_id;
  if v_patient is not null then select p.facility_id into v_parent from public.patients p where p.id=v_patient; if v_parent is null then raise exception 'Reconcile the parent patient facility first'; elsif v_parent<>_target_facility_id then raise exception 'Target facility conflicts with patient facility'; end if; end if;
  if v_exists then update public.encounters set facility_id=_target_facility_id,updated_at=now() where id=_entity_id and facility_id is null; end if;
 elsif _entity_type='service_orders' then
  select s.facility_id,s.patient_id,s.encounter_id,true,jsonb_build_object('department',s.department,'service_name',s.service_name,'status',s.status) into v_source,v_patient,v_ref,v_exists,v_metadata from public.service_orders s where s.id=_entity_id;
  if v_patient is not null then select p.facility_id into v_parent from public.patients p where p.id=v_patient; elsif v_ref is not null then select e.facility_id into v_parent from public.encounters e where e.id=v_ref; end if;
  if v_patient is not null or v_ref is not null then if v_parent is null then raise exception 'Reconcile the parent patient or encounter facility first'; elsif v_parent<>_target_facility_id then raise exception 'Target facility conflicts with parent facility'; end if; end if;
  if v_exists then update public.service_orders set facility_id=_target_facility_id,updated_at=now() where id=_entity_id and facility_id is null; end if;
 elsif _entity_type='department_queues' then
  select q.facility_id,q.patient_id,q.service_order_id,true,jsonb_build_object('department',q.department,'status',q.status,'service_order_id',q.service_order_id) into v_source,v_patient,v_ref,v_exists,v_metadata from public.department_queues q where q.id=_entity_id;
  if v_ref is not null then select s.facility_id into v_parent from public.service_orders s where s.id=v_ref; if v_parent is null then raise exception 'Reconcile the parent service order facility first'; elsif v_parent<>_target_facility_id then raise exception 'Target facility conflicts with parent facility'; end if; end if;
  if v_exists then update public.department_queues set facility_id=_target_facility_id,updated_at=now() where id=_entity_id and facility_id is null; end if;
 elsif _entity_type='lab_orders' then
  select l.facility_id,l.patient_id,l.encounter_id,true,jsonb_build_object('test_name',l.test_name,'status',l.status,'encounter_id',l.encounter_id) into v_source,v_patient,v_ref,v_exists,v_metadata from public.lab_orders l where l.id=_entity_id;
  if v_ref is not null then select e.facility_id into v_parent from public.encounters e where e.id=v_ref; elsif v_patient is not null then select p.facility_id into v_parent from public.patients p where p.id=v_patient; end if;
  if v_patient is not null or v_ref is not null then if v_parent is null then raise exception 'Reconcile the parent encounter or patient facility first'; elsif v_parent<>_target_facility_id then raise exception 'Target facility conflicts with parent facility'; end if; end if;
  if v_exists then update public.lab_orders set facility_id=_target_facility_id,updated_at=now() where id=_entity_id and facility_id is null; end if;
 elsif _entity_type='lab_results' then
  select r.facility_id,r.patient_id,r.lab_order_id,true,jsonb_build_object('lab_order_id',r.lab_order_id,'status',r.status) into v_source,v_patient,v_ref,v_exists,v_metadata from public.lab_results r where r.id=_entity_id;
  select l.facility_id into v_parent from public.lab_orders l where l.id=v_ref; if v_parent is null then raise exception 'Reconcile the parent lab order first'; elsif v_parent<>_target_facility_id then raise exception 'Target facility conflicts with parent lab order'; end if;
  if v_exists then update public.lab_results set facility_id=_target_facility_id where id=_entity_id and facility_id is null; end if;
 elsif _entity_type='imaging_orders' then
  select i.facility_id,i.patient_id,i.encounter_id,true,jsonb_build_object('modality',i.modality,'study_name',i.study_name,'status',i.status) into v_source,v_patient,v_ref,v_exists,v_metadata from public.imaging_orders i where i.id=_entity_id;
  if v_ref is not null then select e.facility_id into v_parent from public.encounters e where e.id=v_ref; elsif v_patient is not null then select p.facility_id into v_parent from public.patients p where p.id=v_patient; end if;
  if v_patient is not null or v_ref is not null then if v_parent is null then raise exception 'Reconcile the parent encounter or patient facility first'; elsif v_parent<>_target_facility_id then raise exception 'Target facility conflicts with parent facility'; end if; end if;
  if v_exists then update public.imaging_orders set facility_id=_target_facility_id,updated_at=now() where id=_entity_id and facility_id is null; end if;
 elsif _entity_type='prescriptions' then
  select rx.facility_id,rx.patient_id,rx.encounter_id,true,jsonb_build_object('medication',coalesce(rx.medication_name,rx.medication),'status',rx.status) into v_source,v_patient,v_ref,v_exists,v_metadata from public.prescriptions rx where rx.id=_entity_id;
  if v_ref is not null then select e.facility_id into v_parent from public.encounters e where e.id=v_ref; elsif v_patient is not null then select p.facility_id into v_parent from public.patients p where p.id=v_patient; end if;
  if v_patient is not null or v_ref is not null then if v_parent is null then raise exception 'Reconcile the parent encounter or patient facility first'; elsif v_parent<>_target_facility_id then raise exception 'Target facility conflicts with parent facility'; end if; end if;
  if v_exists then update public.prescriptions set facility_id=_target_facility_id,updated_at=now() where id=_entity_id and facility_id is null; end if;
 elsif _entity_type='diagnoses' then
  select d.facility_id,d.patient_id,d.encounter_id,true,jsonb_build_object('diagnosis',d.diagnosis,'icd_code',d.icd_code) into v_source,v_patient,v_ref,v_exists,v_metadata from public.diagnoses d where d.id=_entity_id;
  if v_ref is not null then select e.facility_id into v_parent from public.encounters e where e.id=v_ref; elsif v_patient is not null then select p.facility_id into v_parent from public.patients p where p.id=v_patient; end if;
  if v_patient is not null or v_ref is not null then if v_parent is null then raise exception 'Reconcile the parent encounter or patient facility first'; elsif v_parent<>_target_facility_id then raise exception 'Target facility conflicts with parent facility'; end if; end if;
  if v_exists then update public.diagnoses set facility_id=_target_facility_id,updated_at=now() where id=_entity_id and facility_id is null; end if;
 else raise exception 'Unsupported clinical entity type'; end if;
 if not v_exists then raise exception 'Clinical record not found'; end if;
 insert into public.clinical_facility_reconciliation(entity_type,entity_id,source_facility_id,target_facility_id,reason,reviewed_by,metadata)
 values(_entity_type,_entity_id,v_source,_target_facility_id,btrim(_reason),v_actor,v_metadata)
 on conflict(entity_type,entity_id) do update set source_facility_id=excluded.source_facility_id,target_facility_id=excluded.target_facility_id,status='corrected',reason=excluded.reason,reviewed_by=excluded.reviewed_by,reviewed_at=now(),metadata=excluded.metadata;
 perform public.record_system_audit('clinical_facility_reconciled','facility_control_plane',_entity_type,_entity_id,'warning',jsonb_build_object('source_facility_id',v_source,'target_facility_id',_target_facility_id,'reason',btrim(_reason),'actor_id',v_actor));
 return jsonb_build_object('ok',true,'entity_type',_entity_type,'entity_id',_entity_id,'target_facility_id',_target_facility_id);
end $$;
revoke all on function public.reconcile_clinical_facility_record(text,uuid,uuid,text) from public,anon;
grant execute on function public.reconcile_clinical_facility_record(text,uuid,uuid,text) to authenticated;
