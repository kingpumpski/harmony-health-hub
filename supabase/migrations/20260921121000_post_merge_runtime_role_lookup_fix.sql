-- Post-merge runtime compatibility: roles are stored in user_roles, not profiles.
CREATE OR REPLACE FUNCTION public.get_operational_workspace(_module text, _limit integer DEFAULT 200)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v_role text; v_limit integer:=greatest(1,least(coalesce(_limit,200),500)); result jsonb;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 SELECT ur.role::text INTO v_role FROM public.user_roles ur WHERE ur.user_id=auth.uid() ORDER BY ur.created_at DESC LIMIT 1;
 IF v_role IS NULL THEN RAISE EXCEPTION 'Staff profile required'; END IF;
 IF _module='appointments' THEN
  IF v_role NOT IN ('admin','practitioner','nurse','midwife','specialist_nurse','front_desk') THEN RAISE EXCEPTION 'Not authorised'; END IF;
  SELECT jsonb_build_object('appointments',COALESCE(jsonb_agg(to_jsonb(x)),'[]'::jsonb)) INTO result FROM (SELECT a.id,a.patient_id,a.scheduled_at,a.reason,a.status,a.department,a.attending_officer_id,a.treatment_status,a.treatment_notes FROM appointments a JOIN patients p ON p.id=a.patient_id WHERE p.status <> 'inactive' ORDER BY a.scheduled_at ASC LIMIT v_limit)x;
 ELSIF _module='ward' THEN
  IF v_role NOT IN ('admin','practitioner','nurse','midwife','specialist_nurse') THEN RAISE EXCEPTION 'Not authorised'; END IF;
  SELECT jsonb_build_object('wards',COALESCE((SELECT jsonb_agg(to_jsonb(x)) FROM (SELECT id,name,code,specialty,gender_policy,active FROM ward_units WHERE active LIMIT v_limit)x),'[]'::jsonb),'beds',COALESCE((SELECT jsonb_agg(to_jsonb(x)) FROM (SELECT b.id,b.ward_id,b.bed_number,b.status,b.patient_id,b.admission_id FROM ward_beds b LEFT JOIN patients p ON p.id=b.patient_id WHERE b.patient_id IS NULL OR p.status <> 'inactive' ORDER BY b.bed_number LIMIT v_limit)x),'[]'::jsonb)) INTO result;
 ELSIF _module='nursing_care' THEN
  IF v_role NOT IN ('admin','practitioner','nurse','midwife','specialist_nurse') THEN RAISE EXCEPTION 'Not authorised'; END IF;
  SELECT jsonb_build_object('care_plans',COALESCE(jsonb_agg(to_jsonb(x)),'[]'::jsonb)) INTO result FROM (SELECT n.id,n.patient_id,n.problem,n.goal,n.interventions,n.priority,n.status,n.created_at,n.updated_at FROM nursing_care_plans n JOIN patients p ON p.id=n.patient_id WHERE p.status <> 'inactive' ORDER BY n.created_at DESC LIMIT v_limit)x;
 ELSIF _module='emergency' THEN
  IF v_role NOT IN ('admin','practitioner','nurse','midwife','specialist_nurse') THEN RAISE EXCEPTION 'Not authorised'; END IF;
  SELECT jsonb_build_object('cases',COALESCE(jsonb_agg(to_jsonb(x)),'[]'::jsonb)) INTO result FROM (SELECT e.id,e.patient_id,e.chief_complaint,e.acuity,e.arrival_mode,e.status,e.assigned_officer,e.disposition,e.created_at FROM emergency_cases e JOIN patients p ON p.id=e.patient_id WHERE p.status <> 'inactive' ORDER BY e.created_at DESC LIMIT v_limit)x;
 ELSIF _module='handover' THEN
  IF v_role NOT IN ('admin','practitioner','nurse','midwife','specialist_nurse') THEN RAISE EXCEPTION 'Not authorised'; END IF;
  SELECT jsonb_build_object('handovers',COALESCE(jsonb_agg(to_jsonb(x)),'[]'::jsonb)) INTO result FROM (SELECT h.id,h.patient_id,h.shift_label,h.clinical_summary,h.pending_tasks,h.safety_concerns,h.escalation_required,h.acknowledged_at,h.created_at FROM nursing_shift_handovers h JOIN patients p ON p.id=h.patient_id WHERE p.status <> 'inactive' ORDER BY h.created_at DESC LIMIT v_limit)x;
 ELSIF _module='theatre' THEN
  IF v_role NOT IN ('admin','practitioner','nurse','specialist_nurse') THEN RAISE EXCEPTION 'Not authorised'; END IF;
  SELECT jsonb_build_object('cases',COALESCE(jsonb_agg(to_jsonb(x)),'[]'::jsonb)) INTO result FROM (SELECT t.id,t.patient_id,t.procedure_name,t.theatre_name,t.scheduled_start,t.urgency,t.status,t.anesthetist_id FROM theatre_cases t JOIN patients p ON p.id=t.patient_id WHERE p.status <> 'inactive' ORDER BY t.scheduled_start ASC LIMIT v_limit)x;
 ELSIF _module='transfusion' THEN
  IF v_role NOT IN ('admin','practitioner','nurse','midwife','specialist_nurse') THEN RAISE EXCEPTION 'Not authorised'; END IF;
  SELECT jsonb_build_object('records',COALESCE(jsonb_agg(to_jsonb(x)),'[]'::jsonb)) INTO result FROM (SELECT t.id,t.patient_id,t.blood_product,t.unit_identifier,t.blood_group,t.status,t.reaction_observed,t.reaction_notes FROM transfusion_records t JOIN patients p ON p.id=t.patient_id WHERE p.status <> 'inactive' ORDER BY t.created_at DESC LIMIT v_limit)x;
 ELSIF _module='insurance' THEN
  IF v_role NOT IN ('admin','accountant') THEN RAISE EXCEPTION 'Not authorised'; END IF;
  SELECT jsonb_build_object('claims',COALESCE(jsonb_agg(to_jsonb(x)),'[]'::jsonb)) INTO result FROM (SELECT i.id,i.patient_id,i.payer_name,i.member_number,i.claim_number,i.amount_claimed,i.amount_approved,i.amount_paid,i.status,i.rejection_reason,i.service_from,i.service_to,i.created_at FROM insurance_claims i JOIN patients p ON p.id=i.patient_id WHERE p.status <> 'inactive' ORDER BY i.created_at DESC LIMIT v_limit)x;
 ELSIF _module='medication_administration' THEN
  IF v_role NOT IN ('admin','nurse','specialist_nurse','midwife','practitioner') THEN RAISE EXCEPTION 'Not authorised'; END IF;
  SELECT jsonb_build_object('records',COALESCE(jsonb_agg(to_jsonb(x)),'[]'::jsonb),'profiles',COALESCE((SELECT jsonb_agg(to_jsonb(x)) FROM (SELECT id,first_name,last_name,department FROM profiles LIMIT v_limit)x),'[]'::jsonb)) INTO result FROM (SELECT m.id,m.patient_id,m.medication_name,m.dose,m.route,m.scheduled_at,m.administered_at,m.administered_by,m.status,m.reason,m.notes,m.locked_at,m.lock_reason,m.due_window_minutes,m.reopened_at,m.reopen_reason FROM medication_administrations m JOIN patients p ON p.id=m.patient_id WHERE p.status <> 'inactive' ORDER BY m.scheduled_at DESC NULLS LAST LIMIT v_limit)x;
 ELSIF _module='ai_clinical' THEN
  IF v_role NOT IN ('admin','practitioner','nurse','midwife','specialist_nurse','radiologist') THEN RAISE EXCEPTION 'Not authorised'; END IF;
  SELECT jsonb_build_object('sessions',COALESCE(jsonb_agg(to_jsonb(x)),'[]'::jsonb)) INTO result FROM (SELECT id,specialist,status,review_status,created_at,model_provider,model_name FROM ai_clinical_sessions ORDER BY created_at DESC LIMIT v_limit)x;
 ELSIF _module='data_migration' THEN
  IF v_role<>'admin' THEN RAISE EXCEPTION 'Not authorised'; END IF;
  SELECT jsonb_build_object('batches',COALESCE(jsonb_agg(to_jsonb(x)),'[]'::jsonb)) INTO result FROM (SELECT id,entity_type,source_system,source_version,file_name,total_rows,staged_rows,accepted_rows,rejected_rows,status,created_at,approved_at,completed_at FROM data_migration_batches WHERE entity_type='legacy_clinical_records' ORDER BY created_at DESC LIMIT v_limit)x;
 ELSIF _module='facilities' THEN
  IF v_role NOT IN ('admin','front_desk','accountant') THEN RAISE EXCEPTION 'Not authorised'; END IF;
  SELECT jsonb_build_object('facilities',COALESCE(jsonb_agg(to_jsonb(x)),'[]'::jsonb)) INTO result FROM (SELECT id,name,facility_code,facility_type,district,region,dhims2_uid,is_active FROM healthcare_facilities WHERE is_active ORDER BY name LIMIT v_limit)x;
 ELSE RAISE EXCEPTION 'Unsupported workspace module'; END IF;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.get_operational_workspace(text,integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_operational_workspace(text,integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_patient_admission_history(_patient_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v_role text;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 SELECT ur.role::text INTO v_role FROM public.user_roles ur WHERE ur.user_id=auth.uid() ORDER BY ur.created_at DESC LIMIT 1;
 IF v_role IS NULL THEN RAISE EXCEPTION 'Staff profile required'; END IF;
 IF v_role NOT IN ('admin','practitioner','nurse','midwife','specialist_nurse') THEN RAISE EXCEPTION 'Admission history access is not permitted'; END IF;
 IF NOT EXISTS (SELECT 1 FROM patients p WHERE p.id=_patient_id AND p.status <> 'inactive') THEN RAISE EXCEPTION 'Patient not found or inactive'; END IF;
 RETURN COALESCE((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.admitted_at DESC) FROM (SELECT a.id,a.patient_id,a.admitted_at,a.discharged_at,a.ward,a.bed,a.reason,a.status,a.discharge_summary FROM admissions a WHERE a.patient_id=_patient_id ORDER BY a.admitted_at DESC LIMIT 50)x),'[]'::jsonb);
END $$;
REVOKE ALL ON FUNCTION public.get_patient_admission_history(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_patient_admission_history(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_admission_workspace(_limit integer DEFAULT 200)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v_role text; v_limit integer:=greatest(1,least(coalesce(_limit,200),500));
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 SELECT ur.role::text INTO v_role FROM public.user_roles ur WHERE ur.user_id=auth.uid() ORDER BY ur.created_at DESC LIMIT 1;
 IF v_role IS NULL THEN RAISE EXCEPTION 'Staff profile required'; END IF;
 IF v_role NOT IN ('admin','practitioner','nurse','midwife','specialist_nurse') THEN RAISE EXCEPTION 'Admission workspace access is not permitted'; END IF;
 RETURN COALESCE((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.admitted_at DESC) FROM (SELECT a.id,a.patient_id,a.admitted_at,a.discharged_at,a.ward,a.bed,a.reason,a.status,a.discharge_summary FROM admissions a JOIN patients p ON p.id=a.patient_id WHERE p.status <> 'inactive' ORDER BY a.admitted_at DESC LIMIT v_limit)x),'[]'::jsonb);
END $$;
REVOKE ALL ON FUNCTION public.get_admission_workspace(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_admission_workspace(integer) TO authenticated;