BEGIN;

CREATE OR REPLACE FUNCTION public.assert_patient_facility_context(_patient_id uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public
AS $function$
DECLARE uid uuid:=auth.uid(); patient_facility uuid; active_facility uuid:=public.current_user_facility_id();
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
END; $function$;
REVOKE ALL ON FUNCTION public.assert_patient_facility_context(uuid) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.get_patient_admission_history(_patient_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public
AS $function$
DECLARE v_role text;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 SELECT ur.role::text INTO v_role FROM public.user_roles ur WHERE ur.user_id=auth.uid() ORDER BY ur.created_at DESC LIMIT 1;
 IF v_role IS NULL OR v_role NOT IN ('admin','it_admin','practitioner','nurse','midwife','specialist_nurse') THEN RAISE EXCEPTION 'Admission history access is not permitted'; END IF;
 PERFORM public.assert_patient_facility_context(_patient_id);
 RETURN COALESCE((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.admitted_at DESC) FROM (SELECT a.id,a.patient_id,a.admitted_at,a.discharged_at,a.ward,a.bed,a.reason,a.status,a.discharge_summary FROM public.admissions a WHERE a.patient_id=_patient_id ORDER BY a.admitted_at DESC LIMIT 50)x),'[]'::jsonb);
END $function$;

CREATE OR REPLACE FUNCTION public.get_patient_appointments(_patient_id uuid,_limit integer DEFAULT 100)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public
AS $function$
DECLARE v_limit integer:=greatest(1,least(coalesce(_limit,100),100));
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 IF NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'it_admin') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife') OR public.has_role(auth.uid(),'specialist_nurse') OR public.has_role(auth.uid(),'radiologist') OR public.has_role(auth.uid(),'radiology_technician') OR public.has_role(auth.uid(),'front_desk')) THEN RAISE EXCEPTION 'Appointment history access is not permitted'; END IF;
 PERFORM public.assert_patient_facility_context(_patient_id);
 RETURN COALESCE((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.scheduled_at DESC) FROM (SELECT a.id,a.patient_id,a.scheduled_at,a.reason,a.status,a.department,a.attending_officer_id,a.treatment_status,a.treatment_notes FROM public.appointments a WHERE a.patient_id=_patient_id ORDER BY a.scheduled_at DESC LIMIT v_limit)x),'[]'::jsonb);
END $function$;

CREATE OR REPLACE FUNCTION public.get_patient_bmi_context(_patient_id uuid)
RETURNS TABLE(bmi numeric,category text,weight_kg numeric,height_m numeric,recorded_at timestamptz)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public
AS $function$
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 IF NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'it_admin') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife') OR public.has_role(auth.uid(),'pharmacist')) THEN RAISE EXCEPTION 'Clinical access required'; END IF;
 PERFORM public.assert_patient_facility_context(_patient_id);
 RETURN QUERY SELECT t.bmi,public.get_bmi_category(t.bmi),t.weight_kg,t.height_m,t.created_at FROM public.triage_assessments t WHERE t.patient_id=_patient_id AND t.bmi IS NOT NULL ORDER BY t.created_at DESC LIMIT 1;
END; $function$;

CREATE OR REPLACE FUNCTION public.get_patient_directory_record(_patient_id uuid)
RETURNS TABLE(id uuid,patient_code text,first_name text,last_name text,phone text,ghana_card_number text,status text,insurance_provider text,insurance_number text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public
AS $function$
DECLARE can_sensitive boolean;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 IF NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'it_admin') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife') OR public.has_role(auth.uid(),'specialist_nurse') OR public.has_role(auth.uid(),'lab_technician') OR public.has_role(auth.uid(),'radiologist') OR public.has_role(auth.uid(),'radiology_technician') OR public.has_role(auth.uid(),'pharmacist') OR public.has_role(auth.uid(),'accountant') OR public.has_role(auth.uid(),'front_desk') OR public.has_role(auth.uid(),'canteen')) THEN RAISE EXCEPTION 'Not authorized to access the staff patient directory'; END IF;
 PERFORM public.assert_patient_facility_context(_patient_id);
 can_sensitive:=public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'it_admin') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife') OR public.has_role(auth.uid(),'specialist_nurse') OR public.has_role(auth.uid(),'accountant') OR public.has_role(auth.uid(),'front_desk');
 RETURN QUERY SELECT p.id,p.patient_code,p.first_name,p.last_name,p.phone,CASE WHEN can_sensitive THEN p.ghana_card_number ELSE NULL END,p.status::text,CASE WHEN can_sensitive THEN p.insurance_provider ELSE NULL END,CASE WHEN can_sensitive THEN p.insurance_number ELSE NULL END FROM public.patients p WHERE p.id=_patient_id;
END; $function$;

CREATE OR REPLACE FUNCTION public.get_patient_hub_clinical_snapshot(_patient_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public
AS $function$
DECLARE uid uuid:=auth.uid(); is_core boolean; is_lab boolean; is_pharmacy boolean;
BEGIN
 IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 is_core:=public.has_role(uid,'admin') OR public.has_role(uid,'it_admin') OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse') OR public.has_role(uid,'midwife') OR public.has_role(uid,'specialist_nurse'); is_lab:=public.has_role(uid,'lab_technician'); is_pharmacy:=public.has_role(uid,'pharmacist');
 IF NOT(is_core OR is_lab OR is_pharmacy) THEN RAISE EXCEPTION 'Not authorized to access patient clinical history'; END IF;
 PERFORM public.assert_patient_facility_context(_patient_id);
 RETURN jsonb_build_object(
 'vitals',CASE WHEN is_core THEN coalesce((select jsonb_agg(to_jsonb(x) order by x.recorded_at desc) from (select id,recorded_at,systolic,diastolic,pulse_rate,temperature,respiratory_rate,oxygen_saturation,weight_kg,height_cm,bmi,priority,notes,encounter_id from public.vital_signs where patient_id=_patient_id order by recorded_at desc limit 100)x),'[]'::jsonb) ELSE '[]'::jsonb END,
 'encounters',CASE WHEN is_core THEN coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from (select id,created_at,status,encounter_type,chief_complaint,symptoms,clerking_notes,principal_diagnosis,treatment_plan,follow_up_date,practitioner_id,provider_id,admission_id,started_at,completed_at from public.encounters where patient_id=_patient_id order by created_at desc limit 100)x),'[]'::jsonb) ELSE '[]'::jsonb END,
 'labs',CASE WHEN is_core OR is_lab THEN coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from (select id,created_at,test_name,test_category,priority,clinical_notes,status,sample_collected_at,collected_by,encounter_id,ordered_by from public.lab_orders where patient_id=_patient_id order by created_at desc limit 100)x),'[]'::jsonb) ELSE '[]'::jsonb END,
 'prescriptions',CASE WHEN is_core OR is_pharmacy THEN coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from (select id,created_at,medication,medication_name,dosage,frequency,duration,route,status,encounter_id,prescribed_by,dispensed_at from public.prescriptions where patient_id=_patient_id order by created_at desc limit 100)x),'[]'::jsonb) ELSE '[]'::jsonb END,
 'documents',CASE WHEN is_core THEN coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from (select id,created_at,document_type,file_name,storage_path,mime_type,file_size,notes,uploaded_by from public.patient_documents where patient_id=_patient_id order by created_at desc limit 100)x),'[]'::jsonb) ELSE '[]'::jsonb END);
END; $function$;

CREATE OR REPLACE FUNCTION public.get_patient_invoices(_patient_id uuid,_limit integer DEFAULT 100)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public
AS $function$
DECLARE v_limit integer:=greatest(1,least(coalesce(_limit,100),100));
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 IF NOT(public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'it_admin') OR public.has_role(auth.uid(),'accountant') OR public.has_role(auth.uid(),'front_desk') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife') OR public.has_role(auth.uid(),'specialist_nurse')) THEN RAISE EXCEPTION 'Billing history access is not permitted'; END IF;
 PERFORM public.assert_patient_facility_context(_patient_id);
 RETURN COALESCE((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC) FROM (SELECT i.id,i.patient_id,i.invoice_number,i.total_amount,i.status,i.created_at FROM public.invoices i WHERE i.patient_id=_patient_id ORDER BY i.created_at DESC LIMIT v_limit)x),'[]'::jsonb);
END $function$;

CREATE OR REPLACE FUNCTION public.get_patient_current_treatment_snapshot(_patient_id uuid,_admission_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=''
AS $function$
DECLARE uid uuid:=auth.uid(); v_admission public.admissions%ROWTYPE;
BEGIN
 IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 IF NOT(public.current_user_has_role('system_superuser'::public.app_role) OR public.current_user_has_role('admin'::public.app_role) OR public.current_user_has_role('it_admin'::public.app_role) OR public.current_user_has_role('practitioner'::public.app_role) OR public.current_user_has_role('nurse'::public.app_role) OR public.current_user_has_role('midwife'::public.app_role) OR public.current_user_has_role('specialist_nurse'::public.app_role) OR public.current_user_has_role('lab_technician'::public.app_role) OR public.current_user_has_role('pharmacist'::public.app_role)) THEN RAISE EXCEPTION 'Current treatment context is not available for this role'; END IF;
 PERFORM public.assert_patient_facility_context(_patient_id);
 SELECT * INTO v_admission FROM public.admissions WHERE id=_admission_id AND patient_id=_patient_id AND status='admitted';
 IF NOT FOUND THEN RAISE EXCEPTION 'Active admission context not found for patient'; END IF;
 IF NOT public.current_user_has_facility_access(v_admission.facility_id) THEN RAISE EXCEPTION 'Patient treatment context is outside the current facility scope'; END IF;
 RETURN jsonb_build_object('admission',to_jsonb(v_admission),'encounters',COALESCE((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC) FROM (SELECT e.id,e.created_at,e.status,e.encounter_type,e.chief_complaint,e.symptoms,e.clerking_notes,e.principal_diagnosis,e.treatment_plan,e.follow_up_date,e.practitioner_id,e.provider_id,e.admission_id,e.started_at,e.completed_at FROM public.encounters e WHERE e.patient_id=_patient_id AND e.admission_id=_admission_id AND e.status NOT IN('cancelled')) x),'[]'::jsonb),'vitals',COALESCE((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.recorded_at DESC) FROM (SELECT vs.id,vs.recorded_at,vs.systolic,vs.diastolic,vs.pulse_rate,vs.temperature,vs.respiratory_rate,vs.oxygen_saturation,vs.weight_kg,vs.height_cm,vs.bmi,vs.priority,vs.notes,vs.encounter_id FROM public.vital_signs vs JOIN public.encounters e ON e.id=vs.encounter_id WHERE vs.patient_id=_patient_id AND e.admission_id=_admission_id) x),'[]'::jsonb),'labs',COALESCE((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC) FROM (SELECT lo.id,lo.created_at,lo.test_name,lo.test_category,lo.priority,lo.clinical_notes,lo.status,lo.sample_collected_at,lo.collected_by,lo.encounter_id,lo.ordered_by FROM public.lab_orders lo JOIN public.encounters e ON e.id=lo.encounter_id WHERE lo.patient_id=_patient_id AND e.admission_id=_admission_id) x),'[]'::jsonb),'prescriptions',COALESCE((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC) FROM (SELECT pr.id,pr.created_at,pr.medication,pr.medication_name,pr.dosage,pr.frequency,pr.duration,pr.route,pr.status,pr.encounter_id,pr.prescribed_by,pr.dispensed_at FROM public.prescriptions pr JOIN public.encounters e ON e.id=pr.encounter_id WHERE pr.patient_id=_patient_id AND e.admission_id=_admission_id AND pr.status NOT IN('cancelled','voided')) x),'[]'::jsonb),'nursing_notes',COALESCE((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC) FROM (SELECT nn.id,nn.created_at,nn.note_type,nn.note_text,nn.assessment,nn.intervention,nn.evaluation,nn.author_id,nn.encounter_id,nn.admission_id FROM public.nursing_notes nn WHERE nn.patient_id=_patient_id AND nn.admission_id=_admission_id) x),'[]'::jsonb));
END; $function$;

REVOKE ALL ON FUNCTION public.get_patient_admission_history(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_patient_admission_history(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.get_patient_appointments(uuid,integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_patient_appointments(uuid,integer) TO authenticated;
REVOKE ALL ON FUNCTION public.get_patient_bmi_context(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_patient_bmi_context(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.get_patient_directory_record(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_patient_directory_record(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.get_patient_hub_clinical_snapshot(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_patient_hub_clinical_snapshot(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.get_patient_invoices(uuid,integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_patient_invoices(uuid,integer) TO authenticated;
REVOKE ALL ON FUNCTION public.get_patient_current_treatment_snapshot(uuid,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_patient_current_treatment_snapshot(uuid,uuid) TO authenticated;
COMMIT;