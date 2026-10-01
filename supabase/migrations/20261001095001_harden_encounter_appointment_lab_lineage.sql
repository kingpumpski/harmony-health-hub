-- Third tranche: enforce facility lineage on appointment, encounter clerking,
-- laboratory, and prescription workflows.

CREATE OR REPLACE FUNCTION public.create_appointment_workflow(_patient_id uuid,_scheduled_at timestamptz,_department text,_reason text DEFAULT NULL)
RETURNS public.appointments LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
DECLARE uid uuid:=auth.uid(); v_facility uuid:=public.current_user_facility_id(); v_patient_facility uuid; result public.appointments;
BEGIN
 IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 IF NOT(public.has_role(uid,'admin') OR public.has_role(uid,'it_admin') OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse') OR public.has_role(uid,'midwife') OR public.has_role(uid,'specialist_nurse') OR public.has_role(uid,'front_desk')) THEN RAISE EXCEPTION 'Not authorized to schedule appointments'; END IF;
 SELECT facility_id INTO v_patient_facility FROM public.patients WHERE id=_patient_id AND coalesce(status,'active')<>'inactive' FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Active patient does not exist'; END IF;
 IF v_patient_facility IS NULL THEN RAISE EXCEPTION 'Patient facility attribution is unresolved'; END IF;
 IF v_facility IS NULL AND NOT(public.has_role(uid,'admin') OR public.has_role(uid,'it_admin')) THEN RAISE EXCEPTION 'An active facility is required'; END IF;
 IF NOT(public.has_role(uid,'admin') OR public.has_role(uid,'it_admin')) AND v_patient_facility IS DISTINCT FROM v_facility THEN RAISE EXCEPTION 'Patient belongs to a different facility context'; END IF;
 IF _scheduled_at IS NULL THEN RAISE EXCEPTION 'Scheduled time is required'; END IF;
 INSERT INTO public.appointments(patient_id,practitioner_id,department,scheduled_at,duration_minutes,reason,status,notes,created_at,updated_at,treatment_status,facility_id)
 VALUES(_patient_id,CASE WHEN public.has_role(uid,'practitioner') THEN uid ELSE NULL END,NULLIF(pg_catalog.btrim(_department),''),_scheduled_at,30,NULLIF(pg_catalog.btrim(_reason),''),'scheduled',NULL,pg_catalog.now(),pg_catalog.now(),'scheduled',v_patient_facility)
 RETURNING * INTO result;
 RETURN result;
END;$function$;

CREATE OR REPLACE FUNCTION public.save_encounter_draft(_encounter_id uuid,_symptoms text DEFAULT NULL,_clerking_notes text DEFAULT NULL,_treatment_plan text DEFAULT NULL)
RETURNS public.encounters LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
DECLARE uid uuid:=auth.uid(); v_facility uuid:=public.current_user_facility_id(); v public.encounters; v_patient_facility uuid;
BEGIN
 IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 SELECT * INTO v FROM public.encounters WHERE id=_encounter_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Encounter not found'; END IF;
 SELECT facility_id INTO v_patient_facility FROM public.patients WHERE id=v.patient_id FOR SHARE;
 IF v.facility_id IS NULL OR v_patient_facility IS NULL THEN RAISE EXCEPTION 'Encounter or patient facility attribution is unresolved'; END IF;
 IF NOT(public.has_role(uid,'admin') OR public.has_role(uid,'it_admin')) AND (v_facility IS NULL OR v.facility_id IS DISTINCT FROM v_facility OR v_patient_facility IS DISTINCT FROM v_facility) THEN RAISE EXCEPTION 'Encounter belongs to a different facility context'; END IF;
 IF v.practitioner_id<>uid AND NOT(public.has_role(uid,'admin') OR public.has_role(uid,'it_admin')) THEN RAISE EXCEPTION 'Only the encounter creator or an administrator may save this draft'; END IF;
 IF v.status<>'draft' THEN RAISE EXCEPTION 'Only draft encounters can be edited'; END IF;
 UPDATE public.encounters SET symptoms=NULLIF(pg_catalog.btrim(_symptoms),''),clerking_notes=NULLIF(pg_catalog.btrim(_clerking_notes),''),treatment_plan=NULLIF(pg_catalog.btrim(_treatment_plan),''),updated_at=pg_catalog.now() WHERE id=_encounter_id RETURNING * INTO v;
 RETURN v;
END;$function$;

CREATE OR REPLACE FUNCTION public.save_encounter_clerking(_encounter_id uuid,_chief_complaint text DEFAULT NULL,_symptoms text DEFAULT NULL,_history_of_present_illness text DEFAULT NULL,_clerking_notes text DEFAULT NULL,_assessment text DEFAULT NULL,_plan text DEFAULT NULL,_treatment_plan text DEFAULT NULL,_follow_up_date date DEFAULT NULL)
RETURNS public.encounters LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
DECLARE uid uuid:=auth.uid(); v_facility uuid:=public.current_user_facility_id(); v public.encounters; v_patient_facility uuid;
BEGIN
 IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 SELECT * INTO v FROM public.encounters WHERE id=_encounter_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Encounter not found'; END IF;
 SELECT facility_id INTO v_patient_facility FROM public.patients WHERE id=v.patient_id FOR SHARE;
 IF v.facility_id IS NULL OR v_patient_facility IS NULL THEN RAISE EXCEPTION 'Encounter or patient facility attribution is unresolved'; END IF;
 IF NOT(public.has_role(uid,'admin') OR public.has_role(uid,'it_admin')) AND (v_facility IS NULL OR v.facility_id IS DISTINCT FROM v_facility OR v_patient_facility IS DISTINCT FROM v_facility) THEN RAISE EXCEPTION 'Encounter belongs to a different facility context'; END IF;
 IF v.practitioner_id<>uid AND NOT(public.has_role(uid,'admin') OR public.has_role(uid,'it_admin')) THEN RAISE EXCEPTION 'Only the encounter creator or an administrator may save this clerking sheet'; END IF;
 IF v.status<>'draft' THEN RAISE EXCEPTION 'Only draft encounters can be edited'; END IF;
 UPDATE public.encounters SET chief_complaint=NULLIF(pg_catalog.btrim(_chief_complaint),''),symptoms=NULLIF(pg_catalog.btrim(_symptoms),''),history_of_present_illness=NULLIF(pg_catalog.btrim(_history_of_present_illness),''),clerking_notes=NULLIF(pg_catalog.btrim(_clerking_notes),''),assessment=NULLIF(pg_catalog.btrim(_assessment),''),plan=NULLIF(pg_catalog.btrim(_plan),''),treatment_plan=NULLIF(pg_catalog.btrim(_treatment_plan),''),follow_up_date=_follow_up_date,updated_at=pg_catalog.now() WHERE id=_encounter_id RETURNING * INTO v;
 RETURN v;
END;$function$;

CREATE OR REPLACE FUNCTION public.complete_encounter_workflow(_encounter_id uuid)
RETURNS public.encounters LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
DECLARE uid uuid:=auth.uid(); v_facility uuid:=public.current_user_facility_id(); v public.encounters; v_patient_facility uuid;
BEGIN
 IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 IF NOT(public.has_role(uid,'admin') OR public.has_role(uid,'it_admin') OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse') OR public.has_role(uid,'midwife') OR public.has_role(uid,'specialist_nurse')) THEN RAISE EXCEPTION 'Not authorized to complete encounters'; END IF;
 SELECT * INTO v FROM public.encounters WHERE id=_encounter_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Encounter does not exist'; END IF;
 SELECT facility_id INTO v_patient_facility FROM public.patients WHERE id=v.patient_id FOR SHARE;
 IF v.facility_id IS NULL OR v_patient_facility IS NULL THEN RAISE EXCEPTION 'Encounter or patient facility attribution is unresolved'; END IF;
 IF NOT(public.has_role(uid,'admin') OR public.has_role(uid,'it_admin')) AND (v_facility IS NULL OR v.facility_id IS DISTINCT FROM v_facility OR v_patient_facility IS DISTINCT FROM v_facility) THEN RAISE EXCEPTION 'Encounter belongs to a different facility context'; END IF;
 IF v.status IN('completed','cancelled') THEN RAISE EXCEPTION 'Encounter is already closed'; END IF;
 IF v.practitioner_id<>uid AND NOT(public.has_role(uid,'admin') OR public.has_role(uid,'it_admin')) THEN RAISE EXCEPTION 'Only the assigned clinician may complete this encounter'; END IF;
 IF v.principal_diagnosis IS NULL OR NULLIF(pg_catalog.btrim(v.principal_diagnosis),'') IS NULL THEN RAISE EXCEPTION 'Principal diagnosis required'; END IF;
 UPDATE public.encounters SET status='completed',completed_at=coalesce(completed_at,pg_catalog.now()),updated_at=pg_catalog.now() WHERE id=_encounter_id RETURNING * INTO v;
 RETURN v;
END;$function$;

CREATE OR REPLACE FUNCTION public.create_encounter_prescription(_encounter_id uuid,_medication text,_dosage text DEFAULT NULL,_frequency text DEFAULT NULL,_duration text DEFAULT NULL,_diagnosis_id uuid DEFAULT NULL)
RETURNS public.prescriptions LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
DECLARE uid uuid:=auth.uid(); v_enc public.encounters%ROWTYPE; v_patient_facility uuid; v_facility uuid:=public.current_user_facility_id(); result public.prescriptions;
BEGIN
 IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 IF NOT(public.has_role(uid,'admin') OR public.has_role(uid,'it_admin') OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse') OR public.has_role(uid,'midwife') OR public.has_role(uid,'specialist_nurse')) THEN RAISE EXCEPTION 'Not authorized to prescribe'; END IF;
 SELECT * INTO v_enc FROM public.encounters WHERE id=_encounter_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Encounter does not exist'; END IF;
 SELECT facility_id INTO v_patient_facility FROM public.patients WHERE id=v_enc.patient_id FOR SHARE;
 IF v_enc.facility_id IS NULL OR v_patient_facility IS NULL THEN RAISE EXCEPTION 'Encounter or patient facility attribution is unresolved'; END IF;
 IF NOT(public.has_role(uid,'admin') OR public.has_role(uid,'it_admin')) AND (v_facility IS NULL OR v_enc.facility_id IS DISTINCT FROM v_facility OR v_patient_facility IS DISTINCT FROM v_facility) THEN RAISE EXCEPTION 'Encounter belongs to a different facility context'; END IF;
 IF v_enc.status IN('completed','cancelled') THEN RAISE EXCEPTION 'Completed or cancelled encounters are read-only'; END IF;
 IF NULLIF(pg_catalog.btrim(_medication),'') IS NULL THEN RAISE EXCEPTION 'Medication is required'; END IF;
 IF _diagnosis_id IS NULL OR NOT EXISTS(SELECT 1 FROM public.diagnoses d WHERE d.id=_diagnosis_id AND d.encounter_id=_encounter_id AND (d.facility_id=v_enc.facility_id OR d.facility_id IS NULL)) THEN RAISE EXCEPTION 'Selected treatment diagnosis does not belong to this encounter'; END IF;
 INSERT INTO public.prescriptions(encounter_id,patient_id,prescribed_by,medication,dosage,frequency,duration,diagnosis_id,facility_id)
 VALUES(v_enc.id,v_enc.patient_id,uid,pg_catalog.btrim(_medication),NULLIF(pg_catalog.btrim(_dosage),''),NULLIF(pg_catalog.btrim(_frequency),''),NULLIF(pg_catalog.btrim(_duration),''),_diagnosis_id,v_enc.facility_id)
 RETURNING * INTO result;
 RETURN result;
END;$function$;

CREATE OR REPLACE FUNCTION public.create_lab_order_with_payment_gate(_patient_id uuid,_test_name text,_test_category text DEFAULT NULL,_priority text DEFAULT 'routine',_clinical_notes text DEFAULT NULL,_amount numeric DEFAULT 0,_encounter_id uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
DECLARE uid uuid:=auth.uid(); v_facility uuid:=public.current_user_facility_id(); v_patient_facility uuid; v_lab_order_id uuid; v_service_order_id uuid; v_requires_payment boolean:=coalesce(_amount,0)>0; v_service_status text:=case when coalesce(_amount,0)>0 then 'pending_payment_approval' else 'released' end;
BEGIN
 IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 IF NOT(public.has_role(uid,'admin') OR public.has_role(uid,'it_admin') OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse') OR public.has_role(uid,'midwife') OR public.has_role(uid,'lab_technician') OR public.has_role(uid,'front_desk')) THEN RAISE EXCEPTION 'Laboratory order access required'; END IF;
 SELECT facility_id INTO v_patient_facility FROM public.patients WHERE id=_patient_id AND coalesce(status,'active')<>'inactive' FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Active patient does not exist'; END IF;
 IF v_patient_facility IS NULL THEN RAISE EXCEPTION 'Patient facility attribution is unresolved'; END IF;
 IF NOT(public.has_role(uid,'admin') OR public.has_role(uid,'it_admin')) AND (v_facility IS NULL OR v_patient_facility IS DISTINCT FROM v_facility) THEN RAISE EXCEPTION 'Patient belongs to a different facility context'; END IF;
 IF coalesce(_amount,0)<0 THEN RAISE EXCEPTION 'Amount cannot be negative'; END IF;
 IF _encounter_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.encounters e WHERE e.id=_encounter_id AND e.patient_id=_patient_id AND e.facility_id=v_patient_facility AND e.status<>'cancelled') THEN RAISE EXCEPTION 'Selected encounter does not belong to the patient facility context'; END IF;
 INSERT INTO public.lab_orders(patient_id,encounter_id,test_name,test_category,priority,status,clinical_notes,ordered_by,facility_id)
 VALUES(_patient_id,_encounter_id,pg_catalog.btrim(_test_name),NULLIF(pg_catalog.btrim(_test_category),''),coalesce(NULLIF(pg_catalog.btrim(_priority),''),'routine'),'ordered',NULLIF(pg_catalog.btrim(_clinical_notes),''),uid,v_patient_facility)
 RETURNING id INTO v_lab_order_id;
 INSERT INTO public.service_orders(patient_id,encounter_id,department,service_name,amount,unit_price,payment_required,status,requested_by,created_by,related_entity_id,order_type,service_code,notes,facility_id)
 VALUES(_patient_id,_encounter_id,'laboratory',pg_catalog.btrim(_test_name),coalesce(_amount,0),coalesce(_amount,0),v_requires_payment,v_service_status,uid,uid,v_lab_order_id,'lab',NULLIF(pg_catalog.btrim(_test_category),''),NULLIF(pg_catalog.btrim(_clinical_notes),''),v_patient_facility)
 RETURNING id INTO v_service_order_id;
 RETURN jsonb_build_object('lab_order_id',v_lab_order_id,'service_order_id',v_service_order_id,'encounter_id',_encounter_id,'status',v_service_status);
END;$function$;

CREATE OR REPLACE FUNCTION public.collect_lab_sample(_lab_order_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
DECLARE uid uuid:=auth.uid(); v_facility uuid:=public.current_user_facility_id(); o public.lab_orders%ROWTYPE; g public.service_orders%ROWTYPE;
BEGIN
 IF uid IS NULL OR NOT(public.has_role(uid,'admin') OR public.has_role(uid,'it_admin') OR public.has_role(uid,'lab_technician') OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse') OR public.has_role(uid,'midwife') OR public.has_role(uid,'specialist_nurse')) THEN RAISE EXCEPTION 'Laboratory clinical role required'; END IF;
 SELECT * INTO o FROM public.lab_orders WHERE id=_lab_order_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Laboratory order not found'; END IF;
 IF o.facility_id IS NULL THEN RAISE EXCEPTION 'Laboratory order facility attribution is unresolved'; END IF;
 IF NOT(public.has_role(uid,'admin') OR public.has_role(uid,'it_admin')) AND (v_facility IS NULL OR o.facility_id IS DISTINCT FROM v_facility) THEN RAISE EXCEPTION 'Laboratory order belongs to a different facility context'; END IF;
 IF o.status<>'ordered' THEN RAISE EXCEPTION 'Only ordered laboratory requests can have samples collected'; END IF;
 SELECT * INTO g FROM public.service_orders WHERE related_entity_id=o.id AND department='laboratory' AND patient_id=o.patient_id ORDER BY created_at DESC LIMIT 1 FOR UPDATE;
 IF g.id IS NOT NULL AND (g.facility_id IS NULL OR g.facility_id IS DISTINCT FROM o.facility_id) THEN RAISE EXCEPTION 'Laboratory payment record facility lineage is unresolved or mismatched'; END IF;
 IF g.id IS NOT NULL AND g.status NOT IN('released','in_progress','completed') THEN RAISE EXCEPTION 'Payment approval required before sample collection'; END IF;
 UPDATE public.lab_orders SET status='sample_collected',collected_by=uid,sample_collected_at=pg_catalog.now(),updated_at=pg_catalog.now() WHERE id=o.id;
 RETURN jsonb_build_object('lab_order_id',o.id,'status','sample_collected');
END;$function$;

CREATE OR REPLACE FUNCTION public.enter_lab_result_structured(_lab_order_id uuid,_parameter_results jsonb,_result_text text DEFAULT NULL,_interpretation text DEFAULT NULL,_is_abnormal boolean DEFAULT false)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
DECLARE uid uuid:=auth.uid(); v_facility uuid:=public.current_user_facility_id(); o public.lab_orders%ROWTYPE; c public.lab_test_catalogue%ROWTYPE; rid uuid; required_code text;
BEGIN
 IF uid IS NULL OR NOT(public.has_role(uid,'admin') OR public.has_role(uid,'it_admin') OR public.has_role(uid,'lab_technician')) THEN RAISE EXCEPTION 'Laboratory technician role required'; END IF;
 IF jsonb_typeof(coalesce(_parameter_results,'{}'::jsonb))<>'object' THEN RAISE EXCEPTION 'Structured laboratory results must be a JSON object'; END IF;
 SELECT * INTO o FROM public.lab_orders WHERE id=_lab_order_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Laboratory order not found'; END IF;
 IF o.facility_id IS NULL THEN RAISE EXCEPTION 'Laboratory order facility attribution is unresolved'; END IF;
 IF NOT(public.has_role(uid,'admin') OR public.has_role(uid,'it_admin')) AND (v_facility IS NULL OR o.facility_id IS DISTINCT FROM v_facility) THEN RAISE EXCEPTION 'Laboratory order belongs to a different facility context'; END IF;
 IF o.status<>'sample_collected' THEN RAISE EXCEPTION 'Sample must be collected before result entry'; END IF;
 IF EXISTS(SELECT 1 FROM public.lab_results WHERE lab_order_id=o.id AND status IN('completed','approved')) THEN RAISE EXCEPTION 'A completed result already exists for this laboratory order'; END IF;
 IF o.lab_test_catalogue_id IS NOT NULL THEN
  SELECT * INTO c FROM public.lab_test_catalogue WHERE id=o.lab_test_catalogue_id;
  IF c.parameters IS NOT NULL AND jsonb_array_length(c.parameters)>0 THEN
   FOR required_code IN SELECT value->>'code' FROM jsonb_array_elements(c.parameters) value WHERE coalesce((value->>'required')::boolean,false)=true AND nullif(value->>'code','') IS NOT NULL LOOP
    IF NOT(_parameter_results ? required_code) THEN RAISE EXCEPTION 'Required laboratory parameter is missing: %',required_code; END IF;
   END LOOP;
  END IF;
 END IF;
 INSERT INTO public.lab_results(lab_order_id,result_data,parameter_results,interpretation,is_abnormal,entered_by,status,numeric_value,unit,reference_low,reference_high,abnormal_flag,patient_id,result,facility_id)
 VALUES(o.id,jsonb_build_object('value',coalesce(NULLIF(pg_catalog.btrim(_result_text),''),_parameter_results::text)),coalesce(_parameter_results,'{}'::jsonb),_interpretation,_is_abnormal,uid,'completed',NULL,c.unit,c.reference_low,c.reference_high,CASE WHEN _is_abnormal THEN 'abnormal' ELSE 'normal' END,o.patient_id,NULLIF(pg_catalog.btrim(_result_text),''),o.facility_id)
 RETURNING id INTO rid;
 UPDATE public.lab_orders SET status='completed',updated_at=pg_catalog.now() WHERE id=o.id;
 RETURN rid;
END;$function$;

REVOKE ALL ON FUNCTION public.create_appointment_workflow(uuid,timestamptz,text,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.create_appointment_workflow(uuid,timestamptz,text,text) TO authenticated;
REVOKE ALL ON FUNCTION public.save_encounter_draft(uuid,text,text,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.save_encounter_draft(uuid,text,text,text) TO authenticated;
REVOKE ALL ON FUNCTION public.save_encounter_clerking(uuid,text,text,text,text,text,text,text,date) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.save_encounter_clerking(uuid,text,text,text,text,text,text,text,date) TO authenticated;
REVOKE ALL ON FUNCTION public.complete_encounter_workflow(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.complete_encounter_workflow(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.create_encounter_prescription(uuid,text,text,text,text,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.create_encounter_prescription(uuid,text,text,text,text,uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.create_lab_order_with_payment_gate(uuid,text,text,text,text,numeric,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.create_lab_order_with_payment_gate(uuid,text,text,text,text,numeric,uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.collect_lab_sample(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.collect_lab_sample(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.enter_lab_result_structured(uuid,jsonb,text,text,boolean) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.enter_lab_result_structured(uuid,jsonb,text,text,boolean) TO authenticated;