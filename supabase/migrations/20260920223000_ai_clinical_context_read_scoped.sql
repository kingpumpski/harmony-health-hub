CREATE OR REPLACE FUNCTION public.get_ai_clinical_context(_patient_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public
AS $$
DECLARE
 v_role public.app_role;
 v_patient jsonb;
 v_result jsonb;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 SELECT role INTO v_role FROM public.profiles WHERE id=auth.uid();
 IF v_role NOT IN ('admin','practitioner','nurse','midwife','specialist_nurse') THEN RAISE EXCEPTION 'Not authorised'; END IF;

 SELECT to_jsonb(p) - 'national_id' - 'ghana_card_number' - 'passport_number' - 'insurance_member_number'
 INTO v_patient FROM public.patients p WHERE p.id=_patient_id;
 IF v_patient IS NULL THEN RAISE EXCEPTION 'Patient record not found'; END IF;

 SELECT jsonb_build_object(
  'patient',v_patient,
  'appointments',COALESCE((SELECT jsonb_agg(to_jsonb(x)) FROM (
    SELECT a.id,a.patient_id,a.scheduled_at,a.reason,a.status,a.department,a.treatment_status
    FROM public.appointments a WHERE a.patient_id=_patient_id ORDER BY a.scheduled_at DESC LIMIT 25) x),'[]'::jsonb),
  'vitals',COALESCE((SELECT jsonb_agg(to_jsonb(x)) FROM (
    SELECT v.id,v.patient_id,v.recorded_at,v.temperature,v.heart_rate,v.respiratory_rate,v.blood_pressure_systolic,v.blood_pressure_diastolic,v.oxygen_saturation,v.weight_kg,v.height_m
    FROM public.vital_signs v WHERE v.patient_id=_patient_id ORDER BY v.recorded_at DESC LIMIT 25) x),'[]'::jsonb),
  'triage',COALESCE((SELECT jsonb_agg(to_jsonb(x)) FROM (
    SELECT t.id,t.patient_id,t.created_at,t.bmi,t.weight_kg,t.height_m,t.triage_level,t.chief_complaint,t.notes
    FROM public.triage_assessments t WHERE t.patient_id=_patient_id ORDER BY t.created_at DESC LIMIT 25) x),'[]'::jsonb),
  'encounters',COALESCE((SELECT jsonb_agg(to_jsonb(x)) FROM (
    SELECT e.id,e.patient_id,e.created_at,e.status,e.encounter_type,e.department,e.chief_complaint,e.diagnosis,e.notes
    FROM public.encounters e WHERE e.patient_id=_patient_id ORDER BY e.created_at DESC LIMIT 25) x),'[]'::jsonb),
  'labOrders',COALESCE((SELECT jsonb_agg(to_jsonb(x)) FROM (
    SELECT l.id,l.patient_id,l.encounter_id,l.test_name,l.test_category,l.priority,l.clinical_notes,l.status,l.sample_collected_at,l.created_at
    FROM public.lab_orders l WHERE l.patient_id=_patient_id ORDER BY l.created_at DESC LIMIT 50) x),'[]'::jsonb),
  'labResults',COALESCE((SELECT jsonb_agg(to_jsonb(x)) FROM (
    SELECT r.id,r.patient_id,r.lab_order_id,r.result,r.result_data,r.interpretation,r.is_abnormal,r.numeric_value,r.unit,r.reference_low,r.reference_high,r.abnormal_flag,r.status,r.notes,r.created_at
    FROM public.lab_results r WHERE r.patient_id=_patient_id ORDER BY r.created_at DESC LIMIT 100) x),'[]'::jsonb),
  'prescriptions',COALESCE((SELECT jsonb_agg(to_jsonb(x)) FROM (
    SELECT p.id,p.patient_id,p.encounter_id,p.medication,p.medication_name,p.dosage,p.frequency,p.duration,p.route,p.instructions,p.status,p.computed_quantity,p.created_at,p.dispensed_at
    FROM public.prescriptions p WHERE p.patient_id=_patient_id ORDER BY p.created_at DESC LIMIT 50) x),'[]'::jsonb),
  'imagingOrders',COALESCE((SELECT jsonb_agg(to_jsonb(x)) FROM (
    SELECT i.id,i.patient_id,i.encounter_id,i.modality,i.study_name,i.body_site,i.priority,i.clinical_indication,i.status,i.report,i.impression,i.created_at,i.started_at,i.completed_at
    FROM public.imaging_orders i WHERE i.patient_id=_patient_id ORDER BY i.created_at DESC LIMIT 50) x),'[]'::jsonb),
  'procedureNotes',COALESCE((SELECT jsonb_agg(to_jsonb(x)) FROM (
    SELECT n.id,n.patient_id,n.encounter_id,n.procedure_name,n.procedure_code,n.indication,n.technique,n.findings,n.complications,n.post_op_plan,n.status,n.performed_at,n.created_at
    FROM public.procedure_notes n WHERE n.patient_id=_patient_id ORDER BY n.created_at DESC LIMIT 50) x),'[]'::jsonb),
  'anestheticAssessments',COALESCE((SELECT jsonb_agg(to_jsonb(x)) FROM (
    SELECT a.id,a.patient_id,a.encounter_id,a.asa_class,a.airway_assessment,a.cardiovascular,a.respiratory,a.allergies,a.fasting_status,a.conclusions,a.cleared_for_procedure,a.status,a.created_at,a.updated_at
    FROM public.anesthetic_assessments a WHERE a.patient_id=_patient_id ORDER BY a.created_at DESC LIMIT 25) x),'[]'::jsonb)
 ) INTO v_result;
 RETURN v_result;
END; $$;

REVOKE ALL ON FUNCTION public.get_ai_clinical_context(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_ai_clinical_context(uuid) TO authenticated;
