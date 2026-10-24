-- Forward repair for installations where the clinical facility reconciliation RPC is already deployed.
-- lab_results is linked to patients through lab_orders; it does not own patient_id.
create or replace function public.list_unresolved_clinical_facility_records(_limit integer default 100)
returns table(entity_type text,entity_id uuid,patient_id uuid,created_at timestamptz,metadata jsonb)
language sql security definer set search_path=''
as $$ select x.* from (
 select 'patients'::text,p.id,p.id,p.created_at,jsonb_build_object('patient_code',p.patient_code,'first_name',p.first_name,'last_name',p.last_name,'date_of_birth',p.date_of_birth) from public.patients p where p.facility_id is null
 union all select 'encounters',e.id,e.patient_id,e.created_at,jsonb_build_object('encounter_type',e.encounter_type,'status',e.status,'appointment_id',e.appointment_id) from public.encounters e where e.facility_id is null
 union all select 'service_orders',s.id,s.patient_id,s.created_at,jsonb_build_object('department',s.department,'service_name',s.service_name,'status',s.status,'encounter_id',s.encounter_id) from public.service_orders s where s.facility_id is null
 union all select 'department_queues',q.id,q.patient_id,q.created_at,jsonb_build_object('department',q.department,'status',q.status,'service_order_id',q.service_order_id) from public.department_queues q where q.facility_id is null
 union all select 'lab_orders',l.id,l.patient_id,l.created_at,jsonb_build_object('test_name',l.test_name,'status',l.status,'encounter_id',l.encounter_id) from public.lab_orders l where l.facility_id is null
 union all select 'lab_results',r.id,lo.patient_id,r.created_at,jsonb_build_object('lab_order_id',r.lab_order_id,'status',r.status) from public.lab_results r left join public.lab_orders lo on lo.id=r.lab_order_id where r.facility_id is null
 union all select 'imaging_orders',i.id,i.patient_id,i.created_at,jsonb_build_object('modality',i.modality,'study_name',i.study_name,'status',i.status,'encounter_id',i.encounter_id) from public.imaging_orders i where i.facility_id is null
 union all select 'prescriptions',rx.id,rx.patient_id,rx.created_at,jsonb_build_object('medication',coalesce(rx.medication_name,rx.medication),'status',rx.status,'encounter_id',rx.encounter_id) from public.prescriptions rx where rx.facility_id is null
 union all select 'diagnoses',d.id,d.patient_id,d.created_at,jsonb_build_object('diagnosis',d.diagnosis,'icd_code',d.icd_code,'encounter_id',d.encounter_id) from public.diagnoses d where d.facility_id is null
) x where public.has_role(auth.uid(),'admin') or public.has_role(auth.uid(),'it_admin') order by x.created_at nulls last limit greatest(1,least(coalesce(_limit,100),500)); $$;
revoke all on function public.list_unresolved_clinical_facility_records(integer) from public,anon;
grant execute on function public.list_unresolved_clinical_facility_records(integer) to authenticated;
