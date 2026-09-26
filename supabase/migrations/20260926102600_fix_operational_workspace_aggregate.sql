CREATE OR REPLACE FUNCTION public.get_operational_workspace(_module text, _limit integer DEFAULT 200)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='public'
AS $function$
DECLARE v_role text; v_facility uuid:=public.current_user_facility_id(); v_limit integer:=greatest(1,least(coalesce(_limit,200),500)); result jsonb;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 SELECT ur.role::text INTO v_role FROM public.user_roles ur WHERE ur.user_id=auth.uid() ORDER BY ur.created_at DESC LIMIT 1;
 IF v_role IS NULL THEN RAISE EXCEPTION 'Staff profile required'; END IF;
 IF _module='appointments' THEN
  IF v_role NOT IN ('admin','practitioner','nurse','midwife','specialist_nurse','front_desk') THEN RAISE EXCEPTION 'Not authorised'; END IF;
  SELECT jsonb_build_object('appointments',COALESCE((SELECT jsonb_agg(to_jsonb(x)) FROM (SELECT a.id,a.patient_id,a.scheduled_at,a.reason,a.status,a.department,a.attending_officer_id,a.treatment_status,a.treatment_notes FROM appointments a JOIN patients p ON p.id=a.patient_id WHERE p.status <> 'inactive' ORDER BY a.scheduled_at ASC LIMIT v_limit)x),'[]'::jsonb)) INTO result;
 ELSIF _module='ward' THEN
  IF v_role NOT IN ('admin','practitioner','nurse','midwife','specialist_nurse') THEN RAISE EXCEPTION 'Not authorised'; END IF;
  SELECT jsonb_build_object('wards',COALESCE((SELECT jsonb_agg(to_jsonb(x)) FROM (SELECT id,name,code,specialty,gender_policy,active,facility_id FROM ward_units WHERE active AND (v_role='admin' OR facility_id IS NULL OR facility_id=v_facility) ORDER BY name LIMIT v_limit)x),'[]'::jsonb),'beds',COALESCE((SELECT jsonb_agg(to_jsonb(x)) FROM (SELECT b.id,b.ward_id,b.bed_number,b.status,b.patient_id,b.admission_id,b.facility_id FROM ward_beds b WHERE v_role='admin' OR b.facility_id IS NULL OR b.facility_id=v_facility ORDER BY b.bed_number LIMIT v_limit)x),'[]'::jsonb)) INTO result;
 ELSIF _module='nursing_care' THEN
  IF v_role NOT IN ('admin','practitioner','nurse','midwife','specialist_nurse') THEN RAISE EXCEPTION 'Not authorised'; END IF;
  SELECT jsonb_build_object('care_plans',COALESCE((SELECT jsonb_agg(to_jsonb(x)) FROM (SELECT n.id,n.patient_id,n.problem,n.goal,n.interventions,n.priority,n.status,n.created_at,n.updated_at FROM nursing_care_plans n JOIN patients p ON p.id=n.patient_id WHERE p.status <> 'inactive' ORDER BY n.created_at DESC LIMIT v_limit)x),'[]'::jsonb)) INTO result;
 ELSIF _module='emergency' THEN
  IF v_role NOT IN ('admin','practitioner','nurse','midwife','specialist_nurse') THEN RAISE EXCEPTION 'Not authorised'; END IF;
  SELECT jsonb_build_object('cases',COALESCE((SELECT jsonb_agg(to_jsonb(x)) FROM (SELECT e.id,e.patient_id,e.chief_complaint,e.acuity,e.arrival_mode,e.status,e.assigned_officer,e.disposition,e.created_at FROM emergency_cases e JOIN patients p ON p.id=e.patient_id WHERE p.status <> 'inactive' ORDER BY e.created_at DESC LIMIT v_limit)x),'[]'::jsonb)) INTO result;
 ELSIF _module='handover' THEN
  IF v_role NOT IN ('admin','practitioner','nurse','midwife','specialist_nurse') THEN RAISE EXCEPTION 'Not authorised'; END IF;
  SELECT jsonb_build_object('handovers',COALESCE((SELECT jsonb_agg(to_jsonb(x)) FROM (SELECT h.id,h.patient_id,h.shift_label,h.clinical_summary,h.pending_tasks,h.safety_concerns,h.escalation_required,h.acknowledged_at,h.created_at FROM nursing_shift_handovers h JOIN patients p ON p.id=h.patient_id WHERE p.status <> 'inactive' ORDER BY h.created_at DESC LIMIT v_limit)x),'[]'::jsonb)) INTO result;
 ELSIF _module='theatre' THEN
  IF v_role NOT IN ('admin','practitioner','nurse','specialist_nurse') THEN RAISE EXCEPTION 'Not authorised'; END IF;
  SELECT jsonb_build_object('cases',COALESCE((SELECT jsonb_agg(to_jsonb(x)) FROM (SELECT t.id,t.patient_id,t.procedure_name,t.theatre_name,t.scheduled_start,t.urgency,t.status,t.anesthetist_id FROM theatre_cases t JOIN patients p ON p.id=t.patient_id WHERE p.status <> 'inactive' ORDER BY t.scheduled_start ASC LIMIT v_limit)x),'[]'::jsonb)) INTO result;
 ELSIF _module='transfusion' THEN
  IF v_role NOT IN ('admin','practitioner','nurse','midwife','specialist_nurse') THEN RAISE EXCEPTION 'Not authorised'; END IF;
  SELECT jsonb_build_object('records',COALESCE((SELECT jsonb_agg(to_jsonb(x)) FROM (SELECT t.id,t.patient_id,t.blood_product,t.unit_identifier,t.blood_group,t.status,t.reaction_observed,t.reaction_notes FROM transfusion_records t JOIN patients p ON p.id=t.patient_id WHERE p.status <> 'inactive' ORDER BY t.created_at DESC LIMIT v_limit)x),'[]'::jsonb)) INTO result;
 ELSIF _module='insurance' THEN
  IF v_role NOT IN ('admin','accountant') THEN RAISE EXCEPTION 'Not authorised'; END IF;
  SELECT jsonb_build_object('claims',COALESCE((SELECT jsonb_agg(to_jsonb(x)) FROM (SELECT i.id,i.patient_id,i.payer_name,i.member_number,i.claim_number,i.amount_claimed,i.amount_approved,i.amount_paid,i.status,i.rejection_reason,i.service_from,i.service_to,i.created_at FROM insurance_claims i JOIN patients p ON p.id=i.patient_id WHERE p.status <> 'inactive' ORDER BY i.created_at DESC LIMIT v_limit)x),'[]'::jsonb)) INTO result;
 ELSIF _module='medication_administration' THEN
  IF v_role NOT IN ('admin','nurse','specialist_nurse','midwife','practitioner') THEN RAISE EXCEPTION 'Not authorised'; END IF;
  SELECT jsonb_build_object('records',COALESCE((SELECT jsonb_agg(to_jsonb(x)) FROM (SELECT m.id,m.patient_id,m.medication_name,m.dose,m.route,m.scheduled_at,m.administered_at,m.administered_by,m.status,m.reason,m.notes,m.locked_at,m.lock_reason,m.due_window_minutes,m.reopened_at,m.reopen_reason FROM medication_administrations m JOIN patients p ON p.id=m.patient_id WHERE p.status <> 'inactive' ORDER BY m.scheduled_at DESC NULLS LAST LIMIT v_limit)x),'[]'::jsonb)) INTO result;
 ELSIF _module='ai_clinical' THEN
  IF v_role NOT IN ('admin','practitioner','nurse','midwife','specialist_nurse','radiologist') THEN RAISE EXCEPTION 'Not authorised'; END IF;
  SELECT jsonb_build_object('sessions',COALESCE((SELECT jsonb_agg(to_jsonb(x)) FROM (SELECT id,specialist,status,review_status,created_at,model_provider,model_name FROM ai_clinical_sessions ORDER BY created_at DESC LIMIT v_limit)x),'[]'::jsonb)) INTO result;
 ELSIF _module='data_migration' THEN
  IF v_role<>'admin' THEN RAISE EXCEPTION 'Not authorised'; END IF;
  SELECT jsonb_build_object('batches',COALESCE((SELECT jsonb_agg(to_jsonb(x)) FROM (SELECT id,entity_type,source_system,source_version,file_name,total_rows,staged_rows,accepted_rows,rejected_rows,status,created_at,approved_at,completed_at FROM data_migration_batches WHERE entity_type='legacy_clinical_records' ORDER BY created_at DESC LIMIT v_limit)x),'[]'::jsonb)) INTO result;
 ELSIF _module='facilities' THEN
  IF v_role NOT IN ('admin','front_desk','accountant') THEN RAISE EXCEPTION 'Not authorised'; END IF;
  SELECT jsonb_build_object('facilities',COALESCE((SELECT jsonb_agg(to_jsonb(x)) FROM (SELECT id,name,facility_code,facility_type,district,region,dhims2_uid,is_active FROM healthcare_facilities WHERE is_active ORDER BY name LIMIT v_limit)x),'[]'::jsonb)) INTO result;
 ELSE RAISE EXCEPTION 'Unsupported workspace module'; END IF;
 RETURN result;
END $function$;
REVOKE ALL ON FUNCTION public.get_operational_workspace(text,integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_operational_workspace(text,integer) TO authenticated;