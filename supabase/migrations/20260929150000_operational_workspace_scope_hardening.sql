-- Operational workspace scope hardening
-- Preserves existing RPC signatures and all existing operational branches.
-- Adds workspace-specific department/facility boundaries and least-privilege pharmacy projection.

CREATE OR REPLACE FUNCTION public.get_laboratory_workspace(_limit integer DEFAULT 200)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog','public'
AS $$
DECLARE result jsonb; v_department text;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  SELECT NULLIF(lower(trim(p.department)),'') INTO v_department FROM public.profiles p WHERE p.id=auth.uid();
  IF NOT (
    public.has_role(auth.uid(),'admin') OR
    (public.has_role(auth.uid(),'lab_technician') AND (v_department IS NULL OR v_department='laboratory')) OR
    public.has_role(auth.uid(),'practitioner') OR
    (public.has_role(auth.uid(),'nurse') AND (v_department IS NULL OR v_department IN ('laboratory','clinical'))) OR
    (public.has_role(auth.uid(),'midwife') AND (v_department IS NULL OR v_department IN ('laboratory','clinical'))) OR
    (public.has_role(auth.uid(),'specialist_nurse') AND (v_department IS NULL OR v_department IN ('laboratory','clinical'))) OR
    (public.has_role(auth.uid(),'radiologist') AND (v_department IS NULL OR v_department='radiology'))
  ) THEN RAISE EXCEPTION 'Laboratory workspace access is not permitted'; END IF;
  _limit := LEAST(GREATEST(COALESCE(_limit,200),1),500);
  SELECT jsonb_build_object(
    'patients', COALESCE((SELECT jsonb_agg(to_jsonb(p) ORDER BY p.first_name,p.last_name) FROM (SELECT id,first_name,last_name,patient_code FROM public.patients WHERE status <> 'inactive' ORDER BY first_name,last_name LIMIT _limit)p),'[]'::jsonb),
    'catalogue', COALESCE((SELECT jsonb_agg(to_jsonb(c) ORDER BY c.test_name) FROM (SELECT id,test_code,test_name,category,specimen_type,unit,reference_low,reference_high,reference_text,default_charge,active FROM public.lab_test_catalogue WHERE active ORDER BY test_name LIMIT _limit)c),'[]'::jsonb),
    'orders', COALESCE((SELECT jsonb_agg(to_jsonb(o) ORDER BY o.created_at DESC) FROM (SELECT id,patient_id,test_name,test_category,priority,status,created_at,clinical_notes,lab_test_catalogue_id FROM public.lab_orders ORDER BY created_at DESC LIMIT _limit)o),'[]'::jsonb),
    'results', COALESCE((SELECT jsonb_agg(to_jsonb(r) ORDER BY r.entered_at DESC) FROM (SELECT id,lab_order_id,result_data,interpretation,is_abnormal,status,entered_at,approved_at,approved_by,numeric_value,unit,reference_low,reference_high,abnormal_flag FROM public.lab_results ORDER BY entered_at DESC LIMIT _limit)r),'[]'::jsonb)
  ) INTO result;
  RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.get_laboratory_workspace(integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_laboratory_workspace(integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_imaging_workspace(_limit integer DEFAULT 200)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog','public'
AS $$
DECLARE result jsonb; v_department text; v_role text;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  SELECT NULLIF(lower(trim(p.department)),'') INTO v_department FROM public.profiles p WHERE p.id=auth.uid();
  SELECT ur.role::text INTO v_role FROM public.user_roles ur WHERE ur.user_id=auth.uid() ORDER BY ur.created_at DESC LIMIT 1;
  IF NOT (
    public.has_role(auth.uid(),'admin') OR
    (v_role='radiologist' AND (v_department IS NULL OR v_department='radiology')) OR
    (v_role='radiology_technician' AND (v_department IS NULL OR v_department='radiology')) OR
    (v_role='practitioner')
  ) THEN RAISE EXCEPTION 'Imaging workspace access is not permitted'; END IF;
  _limit := LEAST(GREATEST(COALESCE(_limit,200),1),500);
  SELECT jsonb_build_object(
    'patients', COALESCE((SELECT jsonb_agg(to_jsonb(p) ORDER BY p.first_name,p.last_name) FROM (SELECT id,first_name,last_name,patient_code FROM public.patients WHERE status <> 'inactive' ORDER BY first_name,last_name LIMIT _limit)p),'[]'::jsonb),
    'orders', COALESCE((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC) FROM (SELECT io.id,io.patient_id,io.encounter_id,io.modality,io.study_name,io.body_site,io.priority,io.clinical_indication,io.amount,io.status,io.service_order_id,io.requested_by,io.performed_by,io.report,io.impression,io.created_at,io.updated_at,jsonb_build_object('id',p.id,'first_name',p.first_name,'last_name',p.last_name,'patient_code',p.patient_code) patient FROM public.imaging_orders io JOIN public.patients p ON p.id=io.patient_id WHERE io.status <> 'cancelled' ORDER BY io.created_at DESC LIMIT _limit)x),'[]'::jsonb)
  ) INTO result;
  RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.get_imaging_workspace(integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_imaging_workspace(integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_pharmacy_workspace(_limit integer DEFAULT 200)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog','public'
AS $$
DECLARE result jsonb; v_department text; v_pharmacist boolean;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  SELECT NULLIF(lower(trim(p.department)),'') INTO v_department FROM public.profiles p WHERE p.id=auth.uid();
  v_pharmacist := public.has_role(auth.uid(),'pharmacist');
  IF NOT (
    public.has_role(auth.uid(),'admin') OR
    (v_pharmacist AND (v_department IS NULL OR v_department='pharmacy')) OR
    (public.has_role(auth.uid(),'front_desk') AND (v_department IS NULL OR v_department IN ('pharmacy','front desk','front_desk')))
  ) THEN RAISE EXCEPTION 'Pharmacy workspace access is not permitted'; END IF;
  _limit := LEAST(GREATEST(COALESCE(_limit,200),1),500);
  SELECT jsonb_build_object(
    'patients', COALESCE((SELECT jsonb_agg(to_jsonb(p) ORDER BY p.first_name,p.last_name) FROM (SELECT id,first_name,last_name,patient_code FROM public.patients WHERE status <> 'inactive' ORDER BY first_name,last_name LIMIT _limit)p),'[]'::jsonb),
    'inventory', CASE WHEN public.has_role(auth.uid(),'admin') OR v_pharmacist THEN COALESCE((SELECT jsonb_agg(to_jsonb(i) ORDER BY i.drug_name) FROM (SELECT id,drug_name,brand_name,generic_name,form,strength,stock_quantity,reorder_level,unit_price,supplier,batch_number,expiry_date FROM public.pharmacy_inventory WHERE active ORDER BY drug_name LIMIT _limit)i),'[]'::jsonb) ELSE '[]'::jsonb END,
    'prescriptions', CASE WHEN public.has_role(auth.uid(),'admin') OR v_pharmacist THEN COALESCE((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC) FROM (SELECT r.id,r.patient_id,r.medication,r.dosage,r.frequency,r.duration,r.computed_quantity,r.status,r.created_at,jsonb_build_object('id',p.id,'first_name',p.first_name,'last_name',p.last_name,'patient_code',p.patient_code) patients FROM public.prescriptions r JOIN public.patients p ON p.id=r.patient_id WHERE r.status IN ('pending','paid') ORDER BY r.created_at DESC LIMIT _limit)x),'[]'::jsonb) ELSE '[]'::jsonb END,
    'plans', CASE WHEN public.has_role(auth.uid(),'admin') OR v_pharmacist THEN COALESCE((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC) FROM (SELECT d.id,d.patient_id,d.medication_name,d.prepared_quantity,d.service_order_id,d.status,d.created_at,so.status service_order_status,jsonb_build_object('id',p.id,'first_name',p.first_name,'last_name',p.last_name,'patient_code',p.patient_code) patients FROM public.pharmacy_dispensing_plans d JOIN public.patients p ON p.id=d.patient_id LEFT JOIN public.service_orders so ON so.id=d.service_order_id WHERE d.status <> 'cancelled' ORDER BY d.created_at DESC LIMIT _limit)x),'[]'::jsonb) ELSE '[]'::jsonb END,
    'pos_sales', COALESCE((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC) FROM (SELECT s.id,s.patient_id,s.medication,s.quantity,s.total_amount,s.status,s.service_order_id,s.created_at,COALESCE(so.status,s.status) effective_status FROM public.pharmacy_pos_sales s LEFT JOIN public.service_orders so ON so.id=s.service_order_id WHERE s.status NOT IN ('dispensed','cancelled') ORDER BY s.created_at DESC LIMIT _limit)x),'[]'::jsonb)
  ) INTO result;
  RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.get_pharmacy_workspace(integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_pharmacy_workspace(integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_admission_workspace(_limit integer DEFAULT 200)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog','public'
AS $$
DECLARE v_role text; v_facility uuid; v_limit integer:=greatest(1,least(coalesce(_limit,200),500));
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 SELECT ur.role::text INTO v_role FROM public.user_roles ur WHERE ur.user_id=auth.uid() ORDER BY ur.created_at DESC LIMIT 1;
 IF v_role IS NULL THEN RAISE EXCEPTION 'Staff profile required'; END IF;
 IF v_role NOT IN ('admin','practitioner','nurse','midwife','specialist_nurse') THEN RAISE EXCEPTION 'Admission workspace access is not permitted'; END IF;
 v_facility := public.current_user_facility_id();
 RETURN COALESCE((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.admitted_at DESC) FROM (
   SELECT a.id,a.patient_id,a.admitted_at,a.discharged_at,a.ward,a.bed,a.reason,a.status,a.discharge_summary
   FROM public.admissions a JOIN public.patients p ON p.id=a.patient_id
   LEFT JOIN public.ward_beds b ON b.admission_id=a.id LEFT JOIN public.ward_units w ON w.id=b.ward_id
   WHERE p.status <> 'inactive'
     AND (v_role='admin' OR v_facility IS NULL OR b.facility_id IS NULL OR b.facility_id=v_facility OR w.facility_id=v_facility OR b.id IS NULL)
   ORDER BY a.admitted_at DESC LIMIT v_limit)x),'[]'::jsonb);
END $$;
REVOKE ALL ON FUNCTION public.get_admission_workspace(integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_admission_workspace(integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_operational_workspace(_module text, _limit integer DEFAULT 200)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog','public'
AS $$
DECLARE v_role text; v_facility uuid:=public.current_user_facility_id(); v_department text; v_limit integer:=greatest(1,least(coalesce(_limit,200),500)); result jsonb;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 SELECT ur.role::text INTO v_role FROM public.user_roles ur WHERE ur.user_id=auth.uid() ORDER BY ur.created_at DESC LIMIT 1;
 IF v_role IS NULL THEN RAISE EXCEPTION 'Staff profile required'; END IF;
 SELECT NULLIF(lower(trim(p.department)),'') INTO v_department FROM public.profiles p WHERE p.id=auth.uid();
 IF _module='appointments' THEN
  IF v_role NOT IN ('admin','practitioner','nurse','midwife','specialist_nurse','front_desk') THEN RAISE EXCEPTION 'Not authorised'; END IF;
  SELECT jsonb_build_object('appointments',COALESCE((SELECT jsonb_agg(to_jsonb(x)) FROM (SELECT a.id,a.patient_id,a.scheduled_at,a.reason,a.status,a.department,a.attending_officer_id,a.treatment_status,a.treatment_notes FROM public.appointments a JOIN public.patients p ON p.id=a.patient_id WHERE p.status <> 'inactive' AND (v_role IN ('admin','front_desk') OR v_department IS NULL OR a.department IS NULL OR lower(trim(a.department))=v_department) ORDER BY a.scheduled_at ASC LIMIT v_limit)x),'[]'::jsonb)) INTO result;
 ELSIF _module='ward' THEN
  IF v_role NOT IN ('admin','practitioner','nurse','midwife','specialist_nurse') THEN RAISE EXCEPTION 'Not authorised'; END IF;
  SELECT jsonb_build_object('wards',COALESCE((SELECT jsonb_agg(to_jsonb(x)) FROM (SELECT id,name,code,specialty,gender_policy,active,facility_id FROM public.ward_units WHERE active AND (v_role='admin' OR facility_id IS NULL OR facility_id=v_facility) ORDER BY name LIMIT v_limit)x),'[]'::jsonb),'beds',COALESCE((SELECT jsonb_agg(to_jsonb(x)) FROM (SELECT b.id,b.ward_id,b.bed_number,b.status,b.patient_id,b.admission_id,b.facility_id FROM public.ward_beds b WHERE v_role='admin' OR b.facility_id IS NULL OR b.facility_id=v_facility ORDER BY b.bed_number LIMIT v_limit)x),'[]'::jsonb)) INTO result;
 ELSIF _module='nursing_care' THEN
  IF v_role NOT IN ('admin','practitioner','nurse','midwife','specialist_nurse') THEN RAISE EXCEPTION 'Not authorised'; END IF;
  SELECT jsonb_build_object('care_plans',COALESCE((SELECT jsonb_agg(to_jsonb(x)) FROM (SELECT n.id,n.patient_id,n.problem,n.goal,n.interventions,n.priority,n.status,n.created_at,n.updated_at FROM public.nursing_care_plans n JOIN public.patients p ON p.id=n.patient_id WHERE p.status <> 'inactive' ORDER BY n.created_at DESC LIMIT v_limit)x),'[]'::jsonb)) INTO result;
 ELSIF _module='emergency' THEN
  IF v_role NOT IN ('admin','practitioner','nurse','midwife','specialist_nurse') THEN RAISE EXCEPTION 'Not authorised'; END IF;
  SELECT jsonb_build_object('cases',COALESCE((SELECT jsonb_agg(to_jsonb(x)) FROM (SELECT e.id,e.patient_id,e.chief_complaint,e.acuity,e.arrival_mode,e.status,e.assigned_officer,e.disposition,e.created_at FROM public.emergency_cases e JOIN public.patients p ON p.id=e.patient_id WHERE p.status <> 'inactive' ORDER BY e.created_at DESC LIMIT v_limit)x),'[]'::jsonb)) INTO result;
 ELSIF _module='handover' THEN
  IF v_role NOT IN ('admin','practitioner','nurse','midwife','specialist_nurse') THEN RAISE EXCEPTION 'Not authorised'; END IF;
  SELECT jsonb_build_object('handovers',COALESCE((SELECT jsonb_agg(to_jsonb(x)) FROM (SELECT h.id,h.patient_id,h.shift_label,h.clinical_summary,h.pending_tasks,h.safety_concerns,h.escalation_required,h.acknowledged_at,h.created_at FROM public.nursing_shift_handovers h JOIN public.patients p ON p.id=h.patient_id WHERE p.status <> 'inactive' ORDER BY h.created_at DESC LIMIT v_limit)x),'[]'::jsonb)) INTO result;
 ELSIF _module='theatre' THEN
  IF v_role NOT IN ('admin','practitioner','nurse','specialist_nurse') THEN RAISE EXCEPTION 'Not authorised'; END IF;
  SELECT jsonb_build_object('cases',COALESCE((SELECT jsonb_agg(to_jsonb(x)) FROM (SELECT t.id,t.patient_id,t.procedure_name,t.theatre_name,t.scheduled_start,t.urgency,t.status,t.anesthetist_id FROM public.theatre_cases t JOIN public.patients p ON p.id=t.patient_id WHERE p.status <> 'inactive' ORDER BY t.scheduled_start ASC LIMIT v_limit)x),'[]'::jsonb)) INTO result;
 ELSIF _module='transfusion' THEN
  IF v_role NOT IN ('admin','practitioner','nurse','midwife','specialist_nurse') THEN RAISE EXCEPTION 'Not authorised'; END IF;
  SELECT jsonb_build_object('records',COALESCE((SELECT jsonb_agg(to_jsonb(x)) FROM (SELECT t.id,t.patient_id,t.blood_product,t.unit_identifier,t.blood_group,t.status,t.reaction_observed,t.reaction_notes FROM public.transfusion_records t JOIN public.patients p ON p.id=t.patient_id WHERE p.status <> 'inactive' ORDER BY t.created_at DESC LIMIT v_limit)x),'[]'::jsonb)) INTO result;
 ELSIF _module='insurance' THEN
  IF v_role NOT IN ('admin','accountant') THEN RAISE EXCEPTION 'Not authorised'; END IF;
  SELECT jsonb_build_object('claims',COALESCE((SELECT jsonb_agg(to_jsonb(x)) FROM (SELECT i.id,i.patient_id,i.payer_name,i.member_number,i.claim_number,i.amount_claimed,i.amount_approved,i.amount_paid,i.status,i.rejection_reason,i.service_from,i.service_to,i.created_at FROM public.insurance_claims i JOIN public.patients p ON p.id=i.patient_id WHERE p.status <> 'inactive' ORDER BY i.created_at DESC LIMIT v_limit)x),'[]'::jsonb)) INTO result;
 ELSIF _module='medication_administration' THEN
  IF v_role NOT IN ('admin','nurse','specialist_nurse','midwife','practitioner') THEN RAISE EXCEPTION 'Not authorised'; END IF;
  SELECT jsonb_build_object('records',COALESCE((SELECT jsonb_agg(to_jsonb(x)) FROM (SELECT m.id,m.patient_id,m.medication_name,m.dose,m.route,m.scheduled_at,m.administered_at,m.administered_by,m.status,m.reason,m.notes,m.locked_at,m.lock_reason,m.due_window_minutes,m.reopened_at,m.reopen_reason FROM public.medication_administrations m JOIN public.patients p ON p.id=m.patient_id WHERE p.status <> 'inactive' ORDER BY m.scheduled_at DESC NULLS LAST LIMIT v_limit)x),'[]'::jsonb)) INTO result;
 ELSIF _module='ai_clinical' THEN
  IF v_role NOT IN ('admin','practitioner','nurse','midwife','specialist_nurse','radiologist') THEN RAISE EXCEPTION 'Not authorised'; END IF;
  SELECT jsonb_build_object('sessions',COALESCE((SELECT jsonb_agg(to_jsonb(x)) FROM (SELECT id,specialist,status,review_status,created_at,model_provider,model_name FROM public.ai_clinical_sessions ORDER BY created_at DESC LIMIT v_limit)x),'[]'::jsonb)) INTO result;
 ELSIF _module='data_migration' THEN
  IF v_role<>'admin' THEN RAISE EXCEPTION 'Not authorised'; END IF;
  SELECT jsonb_build_object('batches',COALESCE((SELECT jsonb_agg(to_jsonb(x)) FROM (SELECT id,entity_type,source_system,source_version,file_name,total_rows,staged_rows,accepted_rows,rejected_rows,status,created_at,approved_at,completed_at FROM public.data_migration_batches WHERE entity_type='legacy_clinical_records' ORDER BY created_at DESC LIMIT v_limit)x),'[]'::jsonb)) INTO result;
 ELSIF _module='facilities' THEN
  IF v_role NOT IN ('admin','front_desk','accountant') THEN RAISE EXCEPTION 'Not authorised'; END IF;
  SELECT jsonb_build_object('facilities',COALESCE((SELECT jsonb_agg(to_jsonb(x)) FROM (SELECT id,name,facility_code,facility_type,district,region,dhims2_uid,is_active FROM public.healthcare_facilities WHERE is_active ORDER BY name LIMIT v_limit)x),'[]'::jsonb)) INTO result;
 ELSE RAISE EXCEPTION 'Unsupported workspace module'; END IF;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.get_operational_workspace(text,integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_operational_workspace(text,integer) TO authenticated;
