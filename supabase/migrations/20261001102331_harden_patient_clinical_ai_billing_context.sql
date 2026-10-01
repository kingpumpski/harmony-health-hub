BEGIN;

CREATE OR REPLACE FUNCTION public.assert_patient_facility_context(_patient_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = ''
AS $function$
DECLARE
  uid uuid := auth.uid();
  patient_facility uuid;
  active_facility uuid := public.current_user_facility_id();
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF _patient_id IS NULL THEN RAISE EXCEPTION 'Patient is required'; END IF;
  SELECT facility_id INTO patient_facility FROM public.patients WHERE id=_patient_id AND coalesce(status,'active')<>'inactive' FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Patient not found or inactive'; END IF;
  IF patient_facility IS NULL THEN RAISE EXCEPTION 'Patient facility attribution is unresolved'; END IF;
  IF public.has_role(uid,'admin') OR public.has_role(uid,'it_admin') THEN RETURN patient_facility; END IF;
  IF active_facility IS NULL THEN RAISE EXCEPTION 'Active facility context is required'; END IF;
  IF patient_facility IS DISTINCT FROM active_facility THEN RAISE EXCEPTION 'Patient belongs to a different facility context'; END IF;
  RETURN patient_facility;
END;
$function$


CREATE OR REPLACE FUNCTION public.create_ai_clinical_session(_patient_id uuid, _specialist text, _input_snapshot jsonb, _provenance jsonb DEFAULT '{}'::jsonb)
 RETURNS ai_clinical_sessions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = ''
AS $function$
DECLARE uid uuid:=auth.uid(); result public.ai_clinical_sessions;
BEGIN
 IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 IF NOT(public.has_role(uid,'admin') OR public.has_role(uid,'it_admin') OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse') OR public.has_role(uid,'midwife') OR public.has_role(uid,'specialist_nurse') OR public.has_role(uid,'lab_technician') OR public.has_role(uid,'pharmacist')) THEN RAISE EXCEPTION 'Not authorized to create AI clinical sessions'; END IF;
 PERFORM public.assert_patient_facility_context(_patient_id);
 IF _specialist NOT IN('physician','surgeon','neurosurgeon','radiologist','ophthalmologist','pharmacist','nurse') THEN RAISE EXCEPTION 'Unsupported AI specialist'; END IF;
 IF _input_snapshot IS NULL THEN RAISE EXCEPTION 'AI case snapshot is required'; END IF;
 INSERT INTO public.ai_clinical_sessions(patient_id,specialist,status,input_snapshot,provenance,created_by,facility_id)
 SELECT _patient_id,_specialist,'draft',_input_snapshot,coalesce(_provenance,'{}'::jsonb),uid,p.facility_id FROM public.patients p WHERE p.id=_patient_id
 RETURNING * INTO result;
 RETURN result;
END; $function$


CREATE OR REPLACE FUNCTION public.create_ai_report_request(_patient_id uuid, _report_type text DEFAULT 'medical_summary'::text)
 RETURNS ai_report_requests
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = ''
AS $function$
DECLARE uid uuid:=auth.uid(); v_report public.ai_report_requests; v_type text:=lower(pg_catalog.btrim(coalesce(_report_type,'medical_summary')));
BEGIN
 IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 IF _patient_id IS NULL THEN RAISE EXCEPTION 'Patient is required'; END IF;
 PERFORM public.assert_patient_facility_context(_patient_id);
 IF NOT EXISTS(SELECT 1 FROM public.patients p WHERE p.id=_patient_id AND (p.user_id=uid OR public.has_role(uid,'admin') OR public.has_role(uid,'it_admin') OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse') OR public.has_role(uid,'midwife') OR public.has_role(uid,'specialist_nurse') OR public.has_role(uid,'radiologist'))) THEN RAISE EXCEPTION 'Not authorised to request this patient report'; END IF;
 IF v_type<>'medical_summary' THEN RAISE EXCEPTION 'Unsupported report type'; END IF;
 INSERT INTO public.ai_report_requests(patient_id,requested_by,report_type,status) VALUES(_patient_id,uid,v_type,'processing') RETURNING * INTO v_report;
 RETURN v_report;
END; $function$


CREATE OR REPLACE FUNCTION public.create_appointment_workflow(_patient_id uuid, _scheduled_at timestamp with time zone, _department text, _reason text, _consultation_type text, _practitioner_id uuid DEFAULT NULL::uuid)
 RETURNS appointments
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = ''
AS $function$
DECLARE result public.appointments; patient_facility uuid; uid uuid:=auth.uid(); active_facility uuid:=public.current_user_facility_id();
BEGIN
 IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 IF NOT(public.has_role(uid,'admin') OR public.has_role(uid,'it_admin') OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse') OR public.has_role(uid,'midwife') OR public.has_role(uid,'specialist_nurse') OR public.has_role(uid,'front_desk')) THEN RAISE EXCEPTION 'Not authorized to schedule appointments'; END IF;
 patient_facility:=public.assert_patient_facility_context(_patient_id);
 IF NOT(public.has_role(uid,'admin') OR public.has_role(uid,'it_admin')) AND (active_facility IS NULL OR active_facility IS DISTINCT FROM patient_facility) THEN RAISE EXCEPTION 'Patient belongs to a different facility context'; END IF;
 IF _scheduled_at IS NULL THEN RAISE EXCEPTION 'Scheduled time is required'; END IF;
 IF NULLIF(pg_catalog.btrim(_consultation_type),'') IS NULL THEN RAISE EXCEPTION 'Consultation type is required'; END IF;
 IF _practitioner_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.profiles p WHERE p.id=_practitioner_id) THEN RAISE EXCEPTION 'Selected clinician does not exist'; END IF;
 INSERT INTO public.appointments(patient_id,practitioner_id,department,scheduled_at,duration_minutes,reason,status,notes,created_at,updated_at,treatment_status,consultation_type,facility_id)
 VALUES(_patient_id,_practitioner_id,NULLIF(pg_catalog.btrim(_department),''),_scheduled_at,30,NULLIF(pg_catalog.btrim(_reason),''),'scheduled',NULL,now(),now(),'scheduled',NULLIF(pg_catalog.btrim(_consultation_type),''),patient_facility)
 RETURNING * INTO result;
 RETURN result;
END; $function$


CREATE OR REPLACE FUNCTION public.create_encounter_prescription(_encounter_id uuid, _medication text, _dosage text DEFAULT NULL::text, _frequency text DEFAULT NULL::text, _duration text DEFAULT NULL::text)
 RETURNS prescriptions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = ''
AS $function$
DECLARE uid uuid:=auth.uid(); result public.prescriptions; v_encounter public.encounters%ROWTYPE;
BEGIN
 IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 IF NOT(public.has_role(uid,'admin') OR public.has_role(uid,'it_admin') OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse') OR public.has_role(uid,'midwife') OR public.has_role(uid,'specialist_nurse')) THEN RAISE EXCEPTION 'Not authorized to prescribe'; END IF;
 SELECT * INTO v_encounter FROM public.encounters WHERE id=_encounter_id FOR UPDATE;
 IF v_encounter.id IS NULL THEN RAISE EXCEPTION 'Encounter does not exist'; END IF;
 IF v_encounter.status IN('completed','cancelled') THEN RAISE EXCEPTION 'Completed or cancelled encounters are read-only'; END IF;
 PERFORM public.assert_patient_facility_context(v_encounter.patient_id);
 IF v_encounter.facility_id IS NULL OR v_encounter.facility_id IS DISTINCT FROM public.assert_patient_facility_context(v_encounter.patient_id) THEN RAISE EXCEPTION 'Encounter facility attribution is unresolved or mismatched'; END IF;
 IF NULLIF(pg_catalog.btrim(_medication),'') IS NULL THEN RAISE EXCEPTION 'Medication is required'; END IF;
 INSERT INTO public.prescriptions(encounter_id,patient_id,prescribed_by,medication,dosage,frequency,duration,facility_id) VALUES(v_encounter.id,v_encounter.patient_id,uid,pg_catalog.btrim(_medication),NULLIF(pg_catalog.btrim(_dosage),''),NULLIF(pg_catalog.btrim(_frequency),''),NULLIF(pg_catalog.btrim(_duration),''),v_encounter.facility_id) RETURNING * INTO result;
 RETURN result;
END; $function$


CREATE OR REPLACE FUNCTION public.create_patient_document(_patient_id uuid, _document_type text, _file_url text, _notes text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = ''
AS $function$
DECLARE uid uuid:=auth.uid(); v_id uuid;
BEGIN
 IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 IF NOT(public.has_role(uid,'admin') OR public.has_role(uid,'it_admin') OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse') OR public.has_role(uid,'midwife') OR public.has_role(uid,'front_desk')) THEN RAISE EXCEPTION 'Document creation is not permitted'; END IF;
 PERFORM public.assert_patient_facility_context(_patient_id);
 IF NULLIF(pg_catalog.btrim(_document_type),'') IS NULL THEN RAISE EXCEPTION 'Document type is required'; END IF;
 IF NULLIF(pg_catalog.btrim(_file_url),'') IS NULL THEN RAISE EXCEPTION 'Document file reference is required'; END IF;
 INSERT INTO public.patient_documents(patient_id,document_type,storage_path,notes,uploaded_by) VALUES(_patient_id,pg_catalog.btrim(_document_type),pg_catalog.btrim(_file_url),NULLIF(pg_catalog.btrim(_notes),''),uid) RETURNING id INTO v_id;
 RETURN pg_catalog.jsonb_build_object('document_id',v_id);
END; $function$


CREATE OR REPLACE FUNCTION public.get_ai_clinical_context(_patient_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = ''
AS $function$
DECLARE v_patient jsonb; v_result jsonb;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 IF NOT(public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'it_admin') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife') OR public.has_role(auth.uid(),'specialist_nurse')) THEN RAISE EXCEPTION 'Not authorised'; END IF;
 PERFORM public.assert_patient_facility_context(_patient_id);
 SELECT to_jsonb(p)-'national_id'-'ghana_card_number'-'passport_number'-'insurance_member_number' INTO v_patient FROM public.patients p WHERE p.id=_patient_id;
 IF v_patient IS NULL THEN RAISE EXCEPTION 'Patient record not found'; END IF;
 SELECT jsonb_build_object(
 'patient',v_patient,
 'appointments',coalesce((select jsonb_agg(to_jsonb(x)) from (select a.id,a.patient_id,a.scheduled_at,a.reason,a.status,a.department,a.treatment_status from public.appointments a where a.patient_id=_patient_id order by a.scheduled_at desc limit 25)x),'[]'::jsonb),
 'vitals',coalesce((select jsonb_agg(to_jsonb(x)) from (select v.id,v.patient_id,v.recorded_at,v.systolic,v.diastolic,v.pulse_rate,v.temperature,v.respiratory_rate,v.oxygen_saturation,v.weight_kg,v.height_cm,v.bmi,v.priority,v.notes from public.vital_signs v where v.patient_id=_patient_id order by v.recorded_at desc limit 25)x),'[]'::jsonb),
 'triage',coalesce((select jsonb_agg(to_jsonb(x)) from (select t.id,t.patient_id,t.created_at,t.bmi,t.weight_kg,t.height_m,t.priority,t.presenting_complaint,t.clinical_notes from public.triage_assessments t where t.patient_id=_patient_id order by t.created_at desc limit 25)x),'[]'::jsonb),
 'encounters',coalesce((select jsonb_agg(to_jsonb(x)) from (select e.id,e.patient_id,e.created_at,e.status,e.encounter_type,e.chief_complaint,e.principal_diagnosis,e.clerking_notes,e.treatment_plan,e.assessment,e.plan from public.encounters e where e.patient_id=_patient_id order by e.created_at desc limit 25)x),'[]'::jsonb),
 'labOrders',coalesce((select jsonb_agg(to_jsonb(x)) from (select l.id,l.patient_id,l.encounter_id,l.test_name,l.test_category,l.priority,l.clinical_notes,l.status,l.sample_collected_at,l.created_at from public.lab_orders l where l.patient_id=_patient_id order by l.created_at desc limit 50)x),'[]'::jsonb),
 'labResults',coalesce((select jsonb_agg(to_jsonb(x)) from (select r.id,r.patient_id,r.lab_order_id,r.result,r.result_data,r.interpretation,r.is_abnormal,r.numeric_value,r.unit,r.reference_low,r.reference_high,r.abnormal_flag,r.status,r.notes,r.created_at from public.lab_results r where r.patient_id=_patient_id order by r.created_at desc limit 100)x),'[]'::jsonb),
 'prescriptions',coalesce((select jsonb_agg(to_jsonb(x)) from (select p.id,p.patient_id,p.encounter_id,p.medication,p.medication_name,p.dosage,p.frequency,p.duration,p.route,p.instructions,p.status,p.computed_quantity,p.created_at,p.dispensed_at from public.prescriptions p where p.patient_id=_patient_id order by p.created_at desc limit 50)x),'[]'::jsonb),
 'imagingOrders',coalesce((select jsonb_agg(to_jsonb(x)) from (select i.id,i.patient_id,i.encounter_id,i.modality,i.study_name,i.body_site,i.priority,i.clinical_indication,i.status,i.report,i.impression,i.created_at,i.started_at,i.completed_at from public.imaging_orders i where i.patient_id=_patient_id order by i.created_at desc limit 50)x),'[]'::jsonb),
 'procedureNotes',coalesce((select jsonb_agg(to_jsonb(x)) from (select n.id,n.patient_id,n.encounter_id,n.procedure_name,n.procedure_code,n.indication,n.technique,n.findings,n.complications,n.post_op_plan,n.status,n.performed_at,n.created_at from public.procedure_notes n where n.patient_id=_patient_id order by n.created_at desc limit 50)x),'[]'::jsonb),
 'anestheticAssessments',coalesce((select jsonb_agg(to_jsonb(x)) from (select a.id,a.patient_id,a.encounter_id,a.asa_class,a.airway_assessment,a.cardiovascular,a.respiratory,a.allergies,a.fasting_status,a.conclusions,a.cleared_for_procedure,a.status,a.created_at,a.updated_at from public.anesthetic_assessments a where a.patient_id=_patient_id order by a.created_at desc limit 25)x),'[]'::jsonb),
 'admissions',coalesce((select jsonb_agg(to_jsonb(x)) from (select a.id,a.patient_id,a.admitted_at,a.discharged_at,a.ward,a.bed,a.reason,a.status,a.discharge_summary from public.admissions a where a.patient_id=_patient_id order by a.admitted_at desc limit 50)x),'[]'::jsonb)
 ) INTO v_result;
 RETURN v_result;
END; $function$


CREATE OR REPLACE FUNCTION public.get_attending_patient_history(_patient_id uuid, _current_encounter_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path = ''
AS $function$
DECLARE r jsonb; uid uuid:=auth.uid();
BEGIN
 IF uid IS NULL OR NOT(public.has_role(uid,'admin') OR public.has_role(uid,'it_admin') OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse') OR public.has_role(uid,'midwife') OR public.has_role(uid,'specialist_nurse')) THEN RAISE EXCEPTION 'Not authorized to view attending clinical history'; END IF;
 PERFORM public.assert_patient_facility_context(_patient_id);
 IF _current_encounter_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.encounters WHERE id=_current_encounter_id AND patient_id=_patient_id) THEN RAISE EXCEPTION 'Encounter does not belong to patient'; END IF;
 SELECT jsonb_build_object('patient',(SELECT jsonb_build_object('id',p.id,'patient_code',p.patient_code,'name',concat_ws(' ',p.first_name,p.last_name),'blood_group',p.blood_group,'genotype',p.genotype,'allergies',NULLIF(trim(p.allergies),''),'chronic_conditions',NULLIF(trim(p.chronic_conditions),'')) FROM public.patients p WHERE p.id=_patient_id),'prior_encounters',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC) FROM (SELECT e.id,e.created_at,e.status,NULLIF(trim(e.principal_diagnosis),'') principal_diagnosis,NULLIF(left(trim(e.symptoms),280),'') presenting_symptoms,NULLIF(left(trim(e.treatment_plan),360),'') prior_treatment_plan FROM public.encounters e WHERE e.patient_id=_patient_id AND (_current_encounter_id IS NULL OR e.id<>_current_encounter_id) ORDER BY e.created_at DESC LIMIT 8)x),'[]'::jsonb),'major_diagnoses',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.last_seen DESC) FROM (SELECT NULLIF(trim(d.diagnosis),'') diagnosis,max(e.created_at) last_seen,count(*)::int occurrences FROM public.diagnoses d JOIN public.encounters e ON e.id=d.encounter_id WHERE e.patient_id=_patient_id AND (_current_encounter_id IS NULL OR e.id<>_current_encounter_id) AND NULLIF(trim(d.diagnosis),'') IS NOT NULL GROUP BY NULLIF(trim(d.diagnosis),'') ORDER BY last_seen DESC LIMIT 12)x),'[]'::jsonb),'abnormal_labs',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.entered_at DESC) FROM (SELECT lo.id lab_order_id,lo.test_name,lo.test_category,lr.interpretation,lr.result_data,lr.entered_at FROM public.lab_orders lo JOIN public.lab_results lr ON lr.lab_order_id=lo.id WHERE lo.patient_id=_patient_id AND lr.is_abnormal=true ORDER BY lr.entered_at DESC LIMIT 8)x),'[]'::jsonb),'recent_prescriptions',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC) FROM (SELECT pr.medication,pr.dosage,pr.frequency,pr.duration,pr.status,pr.created_at FROM public.prescriptions pr WHERE pr.patient_id=_patient_id AND pr.status<>'cancelled' ORDER BY pr.created_at DESC LIMIT 8)x),'[]'::jsonb),'latest_triage',(SELECT to_jsonb(x) FROM (SELECT v.recorded_at,v.priority,v.systolic,v.diastolic,v.pulse_rate,v.temperature,v.respiratory_rate,v.oxygen_saturation,v.weight_kg,v.bmi,NULLIF(left(trim(v.notes),280),'') notes FROM public.vital_signs v WHERE v.patient_id=_patient_id ORDER BY v.recorded_at DESC LIMIT 1)x),'active_admission',(SELECT to_jsonb(x) FROM (SELECT a.admitted_at,a.ward,a.bed,a.status,NULLIF(left(trim(a.notes),280),'') notes FROM public.admissions a WHERE a.patient_id=_patient_id AND a.status='admitted' ORDER BY a.admitted_at DESC LIMIT 1)x)) INTO r; RETURN r;
END; $function$


CREATE OR REPLACE FUNCTION public.get_billing_window(_patient_id uuid, _at timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = ''
AS $function$
DECLARE v_patient public.patients; v_encounter uuid; v_invoice uuid; v_start timestamptz:=date_trunc('day',coalesce(_at,now())); v_end timestamptz:=date_trunc('day',coalesce(_at,now()))+interval '1 day'-interval '1 microsecond'; v_insured boolean:=false; v_insurer text; v_insurer_id uuid; v_credit numeric:=0; v_total numeric:=0; v_insurance numeric:=0; v_topup numeric:=0; v_items jsonb; v_account_id text;
BEGIN
 IF auth.uid() IS NULL OR NOT(public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'it_admin') OR public.has_role(auth.uid(),'accountant') OR public.has_role(auth.uid(),'front_desk')) THEN RAISE EXCEPTION 'Billing access denied'; END IF;
 PERFORM public.assert_patient_facility_context(_patient_id);
 SELECT * INTO v_patient FROM public.patients WHERE id=_patient_id AND coalesce(status,'active')<>'inactive';
 IF v_patient.id IS NULL THEN RAISE EXCEPTION 'Active patient not found'; END IF;
 SELECT e.id INTO v_encounter FROM public.encounters e WHERE e.patient_id=_patient_id AND e.created_at<=v_end AND (e.completed_at IS NULL OR e.completed_at>=v_start) AND e.facility_id=v_patient.facility_id ORDER BY coalesce(e.started_at,e.created_at) DESC LIMIT 1;
 v_insured:=NULLIF(trim(v_patient.insurance_provider),'') IS NOT NULL AND NULLIF(trim(v_patient.insurance_number),'') IS NOT NULL AND (v_patient.insurance_expiry IS NULL OR v_patient.insurance_expiry>=_at::date);
 IF v_insured THEN
   v_insurer_id:=v_patient.insurance_company_id;
   IF v_insurer_id IS NULL THEN SELECT c.insurance_company_id,c.payer_name INTO v_insurer_id,v_insurer FROM public.insurance_cases c WHERE c.patient_id=_patient_id AND c.eligibility_status='eligible' AND c.created_at<=v_end ORDER BY c.updated_at DESC LIMIT 1; END IF;
   IF v_insurer_id IS NOT NULL THEN SELECT name INTO v_insurer FROM public.insurance_companies WHERE id=v_insurer_id; END IF;
   v_insurer:=coalesce(v_insurer,(SELECT c.payer_name FROM public.insurance_cases c WHERE c.patient_id=_patient_id AND c.eligibility_status='eligible' AND c.created_at<=v_end ORDER BY c.updated_at DESC LIMIT 1),v_patient.insurance_provider);
 END IF;
 PERFORM public.prepare_patient_billable_items(_patient_id,v_start,v_end);
 SELECT i.id INTO v_invoice FROM public.invoices i WHERE i.patient_id=_patient_id AND i.status IN('pending','partially_paid') AND i.facility_id=v_patient.facility_id ORDER BY i.created_at DESC LIMIT 1 FOR UPDATE;
 IF v_invoice IS NULL THEN RAISE EXCEPTION 'Billing invoice could not be prepared'; END IF;
 IF v_encounter IS NOT NULL THEN UPDATE public.invoices SET encounter_id=coalesce(encounter_id,v_encounter),updated_at=now() WHERE id=v_invoice; END IF;
 UPDATE public.invoice_items ii SET insurance_charge=CASE WHEN NOT v_insured THEN 0 ELSE least(ii.amount,greatest(coalesce((SELECT t.insurance_charge FROM public.insurance_service_tariffs t WHERE ((v_insurer_id IS NOT NULL AND t.insurance_company_id=v_insurer_id) OR (v_insurer_id IS NULL AND lower(t.payer_name)=lower(v_insurer))) AND t.service_code=ii.service_code AND t.active AND t.effective_from<=_at::date AND (t.effective_to IS NULL OR t.effective_to>=_at::date) ORDER BY t.effective_from DESC LIMIT 1),0)*greatest(ii.quantity,1),0)) END,top_up=CASE WHEN NOT v_insured THEN greatest(ii.amount-coalesce((SELECT sum(ip.amount) FROM public.invoice_item_payments ip WHERE ip.invoice_item_id=ii.id),0),0) ELSE greatest(ii.amount-least(ii.amount,greatest(coalesce((SELECT t.insurance_charge FROM public.insurance_service_tariffs t WHERE ((v_insurer_id IS NOT NULL AND t.insurance_company_id=v_insurer_id) OR (v_insurer_id IS NULL AND lower(t.payer_name)=lower(v_insurer))) AND t.service_code=ii.service_code AND t.active AND t.effective_from<=_at::date AND (t.effective_to IS NULL OR t.effective_to>=_at::date) ORDER BY t.effective_from DESC LIMIT 1),0)*greatest(ii.quantity,1),0)),0) END,updated_at=now() WHERE ii.invoice_id=v_invoice;
 SELECT coalesce(sum(ii.amount),0),coalesce(sum(ii.insurance_charge),0),coalesce(sum(case when v_insured then ii.top_up else ii.amount end),0) INTO v_total,v_insurance,v_topup FROM public.invoice_items ii WHERE ii.invoice_id=v_invoice;
 SELECT coalesce(sum(case when entry_type in('deposit','credit') then amount else -amount end),0) INTO v_credit FROM public.patient_account_credits WHERE patient_id=_patient_id;
 SELECT coalesce(jsonb_agg(jsonb_build_object('invoice_item_id',ii.id,'source_type',ii.source_type,'source_id',ii.source_id,'description',ii.description,'category',ii.category,'department',ii.department,'quantity',ii.quantity,'unit_price',ii.unit_price,'charge',ii.amount,'insurance_charge',coalesce(ii.insurance_charge,0),'top_up',case when v_insured then coalesce(ii.top_up,ii.amount) else ii.amount end,'paid_amount',coalesce((select sum(ip.amount) from public.invoice_item_payments ip where ip.invoice_item_id=ii.id),0),'outstanding_amount',greatest(ii.amount-coalesce((select sum(ip.amount) from public.invoice_item_payments ip where ip.invoice_item_id=ii.id),0),'0'::numeric),'billed_at',ii.billed_at,'service_order_id',so.id,'service_order_status',so.status) order by ii.created_at),'[]'::jsonb) INTO v_items FROM public.invoice_items ii LEFT JOIN LATERAL(select s.id,s.status from public.service_orders s where s.invoice_item_id=ii.id order by s.created_at desc limit 1)so on true WHERE ii.invoice_id=v_invoice;
 SELECT i.invoice_number INTO v_account_id FROM public.invoices i WHERE i.id=v_invoice;
 RETURN jsonb_build_object('invoice_id',v_invoice,'account_id',v_account_id,'records_folder_id',v_patient.patient_code,'patient_name',concat_ws(' ',v_patient.first_name,v_patient.last_name),'patient_type',case when v_insured then 'Insured' else 'Cash / Non-Insured' end,'insurance_name',case when v_insured then v_insurer else null end,'encounter_id',v_encounter,'date_time',coalesce(_at,now()),'total_amount',round(v_total,2),'insurance_total',round(v_insurance,2),'top_up_total',round(v_topup,2),'credit_balance',round(v_credit,2),'amount_due',round(v_topup-v_credit,2),'items',v_items);
END; $function$


REVOKE ALL ON FUNCTION public.assert_patient_facility_context(uuid) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.create_appointment_workflow(uuid,timestamptz,text,text,text,uuid) FROM PUBLIC,anon; GRANT EXECUTE ON FUNCTION public.create_appointment_workflow(uuid,timestamptz,text,text,text,uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.create_ai_clinical_session(uuid,text,jsonb,jsonb) FROM PUBLIC,anon; GRANT EXECUTE ON FUNCTION public.create_ai_clinical_session(uuid,text,jsonb,jsonb) TO authenticated;
REVOKE ALL ON FUNCTION public.create_ai_report_request(uuid,text) FROM PUBLIC,anon; GRANT EXECUTE ON FUNCTION public.create_ai_report_request(uuid,text) TO authenticated;
REVOKE ALL ON FUNCTION public.get_ai_clinical_context(uuid) FROM PUBLIC,anon; GRANT EXECUTE ON FUNCTION public.get_ai_clinical_context(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.get_attending_patient_history(uuid,uuid) FROM PUBLIC,anon; GRANT EXECUTE ON FUNCTION public.get_attending_patient_history(uuid,uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.get_billing_window(uuid,timestamptz) FROM PUBLIC,anon; GRANT EXECUTE ON FUNCTION public.get_billing_window(uuid,timestamptz) TO authenticated;
REVOKE ALL ON FUNCTION public.create_patient_document(uuid,text,text,text) FROM PUBLIC,anon; GRANT EXECUTE ON FUNCTION public.create_patient_document(uuid,text,text,text) TO authenticated;
REVOKE ALL ON FUNCTION public.create_encounter_prescription(uuid,text,text,text,text) FROM PUBLIC,anon; GRANT EXECUTE ON FUNCTION public.create_encounter_prescription(uuid,text,text,text,text) TO authenticated;

COMMIT;
