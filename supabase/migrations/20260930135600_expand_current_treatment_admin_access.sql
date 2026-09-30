-- Expand current-treatment Patient Hub access to platform administrators while preserving facility scope.
CREATE OR REPLACE FUNCTION public.get_patient_current_treatment_snapshot(_patient_id uuid,_admission_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $function$
DECLARE uid uuid:=auth.uid(); v_admission public.admissions%ROWTYPE;
BEGIN
IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
IF NOT(public.current_user_has_role('system_superuser'::public.app_role) OR public.current_user_has_role('admin'::public.app_role) OR public.current_user_has_role('it_admin'::public.app_role) OR public.current_user_has_role('practitioner'::public.app_role) OR public.current_user_has_role('nurse'::public.app_role) OR public.current_user_has_role('midwife'::public.app_role) OR public.current_user_has_role('specialist_nurse'::public.app_role) OR public.current_user_has_role('lab_technician'::public.app_role) OR public.current_user_has_role('pharmacist'::public.app_role)) THEN RAISE EXCEPTION 'Current treatment context is not available for this role'; END IF;
SELECT * INTO v_admission FROM public.admissions WHERE id=_admission_id AND patient_id=_patient_id AND status='admitted';
IF NOT FOUND THEN RAISE EXCEPTION 'Active admission context not found for patient'; END IF;
IF NOT public.current_user_has_facility_access(v_admission.facility_id) THEN RAISE EXCEPTION 'Patient treatment context is outside the current facility scope'; END IF;
RETURN jsonb_build_object(
'admission',to_jsonb(v_admission),
'encounters',COALESCE((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC) FROM (SELECT e.id,e.created_at,e.status,e.encounter_type,e.chief_complaint,e.symptoms,e.clerking_notes,e.principal_diagnosis,e.treatment_plan,e.follow_up_date,e.practitioner_id,e.provider_id,e.admission_id,e.started_at,e.completed_at FROM public.encounters e WHERE e.patient_id=_patient_id AND e.admission_id=_admission_id AND e.status NOT IN('cancelled')) x),'[]'::jsonb),
'vitals',COALESCE((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.recorded_at DESC) FROM (SELECT vs.id,vs.recorded_at,vs.systolic,vs.diastolic,vs.pulse_rate,vs.temperature,vs.respiratory_rate,vs.oxygen_saturation,vs.weight_kg,vs.height_cm,vs.bmi,vs.priority,vs.notes,vs.encounter_id FROM public.vital_signs vs JOIN public.encounters e ON e.id=vs.encounter_id WHERE vs.patient_id=_patient_id AND e.admission_id=_admission_id) x),'[]'::jsonb),
'labs',COALESCE((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC) FROM (SELECT lo.id,lo.created_at,lo.test_name,lo.test_category,lo.priority,lo.clinical_notes,lo.status,lo.sample_collected_at,lo.collected_by,lo.encounter_id,lo.ordered_by FROM public.lab_orders lo JOIN public.encounters e ON e.id=lo.encounter_id WHERE lo.patient_id=_patient_id AND e.admission_id=_admission_id) x),'[]'::jsonb),
'prescriptions',COALESCE((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC) FROM (SELECT pr.id,pr.created_at,pr.medication,pr.medication_name,pr.dosage,pr.frequency,pr.duration,pr.route,pr.status,pr.encounter_id,pr.prescribed_by,pr.dispensed_at FROM public.prescriptions pr JOIN public.encounters e ON e.id=pr.encounter_id WHERE pr.patient_id=_patient_id AND e.admission_id=_admission_id AND pr.status NOT IN('cancelled','voided')) x),'[]'::jsonb),
'nursing_notes',COALESCE((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC) FROM (SELECT nn.id,nn.created_at,nn.note_type,nn.note_text,nn.assessment,nn.intervention,nn.evaluation,nn.author_id,nn.encounter_id,nn.admission_id FROM public.nursing_notes nn WHERE nn.patient_id=_patient_id AND nn.admission_id=_admission_id) x),'[]'::jsonb)
);
END; $function$;
REVOKE ALL ON FUNCTION public.get_patient_current_treatment_snapshot(uuid,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_patient_current_treatment_snapshot(uuid,uuid) TO authenticated;
