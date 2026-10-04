-- Harden direct clinical documentation/procedure writes with patient facility lineage.
CREATE OR REPLACE FUNCTION public.create_nursing_note(_patient_id uuid,_note_text text,_note_type text DEFAULT 'progress'::text,_assessment text DEFAULT NULL::text,_intervention text DEFAULT NULL::text,_evaluation text DEFAULT NULL::text,_encounter_id uuid DEFAULT NULL::uuid,_admission_id uuid DEFAULT NULL::uuid)
RETURNS public.nursing_notes LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
DECLARE v public.nursing_notes; pf uuid; uid uuid:=auth.uid();
BEGIN
 IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 IF NOT(public.current_user_has_role('admin'::public.app_role) OR public.current_user_has_role('nurse'::public.app_role) OR public.current_user_has_role('specialist_nurse'::public.app_role) OR public.current_user_has_role('midwife'::public.app_role) OR public.current_user_has_role('practitioner'::public.app_role)) THEN RAISE EXCEPTION 'Nursing documentation is not permitted for this role'; END IF;
 IF NULLIF(pg_catalog.btrim(_note_text),'') IS NULL THEN RAISE EXCEPTION 'Nursing note text is required'; END IF;
 pf:=public.assert_patient_facility_context(_patient_id);
 IF _encounter_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.encounters e WHERE e.id=_encounter_id AND e.patient_id=_patient_id AND e.facility_id=pf) THEN RAISE EXCEPTION 'Encounter does not belong to this patient facility'; END IF;
 IF _admission_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.admissions a WHERE a.id=_admission_id AND a.patient_id=_patient_id) THEN RAISE EXCEPTION 'Admission does not belong to this patient'; END IF;
 IF _encounter_id IS NULL AND _admission_id IS NULL THEN RAISE EXCEPTION 'A nursing note must be linked to an encounter or admission'; END IF;
 INSERT INTO public.nursing_notes(facility_id,patient_id,encounter_id,admission_id,author_id,note_type,note_text,assessment,intervention,evaluation)
 VALUES(pf,_patient_id,_encounter_id,_admission_id,uid,COALESCE(NULLIF(pg_catalog.btrim(_note_type),''),'progress'),pg_catalog.btrim(_note_text),NULLIF(pg_catalog.btrim(_assessment),''),NULLIF(pg_catalog.btrim(_intervention),''),NULLIF(pg_catalog.btrim(_evaluation),'')) RETURNING * INTO v;
 RETURN v;
END;$function$;

CREATE OR REPLACE FUNCTION public.create_ophthalmology_exam(_patient_id uuid,_visual_acuity text,_refraction text,_keratometry text,_intraocular_pressure numeric,_color_vision text,_fundus_notes text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
DECLARE v_id uuid; pf uuid;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 IF NOT(public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner')) THEN RAISE EXCEPTION 'Ophthalmology clinical role required'; END IF;
 pf:=public.assert_patient_facility_context(_patient_id);
 IF _intraocular_pressure IS NOT NULL AND _intraocular_pressure<0 THEN RAISE EXCEPTION 'Intraocular pressure cannot be negative'; END IF;
 INSERT INTO public.ophthalmology_exams(facility_id,patient_id,visual_acuity,refraction,keratometry,intraocular_pressure,color_vision,fundus_notes,performed_by)
 VALUES(pf,_patient_id,NULLIF(pg_catalog.btrim(_visual_acuity),''),NULLIF(pg_catalog.btrim(_refraction),''),NULLIF(pg_catalog.btrim(_keratometry),''),_intraocular_pressure,NULLIF(pg_catalog.btrim(_color_vision),''),NULLIF(pg_catalog.btrim(_fundus_notes),''),auth.uid()) RETURNING id INTO v_id;
 RETURN v_id;
END;$function$;

CREATE OR REPLACE FUNCTION public.create_procedure_note(_patient_id uuid,_procedure_name text,_template_used text,_indication text,_technique text,_findings text,_complications text,_post_op_plan text,_charge_amount numeric,_service_order_id uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
DECLARE uid uuid:=auth.uid(); sid public.service_orders%ROWTYPE; v_id uuid; pf uuid;
BEGIN
 IF uid IS NULL OR NOT(public.has_role(uid,'admin') OR public.has_role(uid,'practitioner') OR public.has_role(uid,'specialist_nurse') OR public.has_role(uid,'nurse') OR public.has_role(uid,'midwife')) THEN RAISE EXCEPTION 'Clinical role required'; END IF;
 pf:=public.assert_patient_facility_context(_patient_id);
 IF COALESCE(_charge_amount,0)<0 THEN RAISE EXCEPTION 'Charge amount cannot be negative'; END IF;
 IF COALESCE(_charge_amount,0)>0 THEN
  IF _service_order_id IS NULL THEN RAISE EXCEPTION 'A released service order is required for a chargeable procedure'; END IF;
  SELECT * INTO sid FROM public.service_orders WHERE id=_service_order_id AND facility_id=pf FOR UPDATE;
  IF NOT FOUND OR sid.patient_id<>_patient_id OR sid.department<>'procedure' THEN RAISE EXCEPTION 'Procedure service order linkage is invalid'; END IF;
  IF sid.status NOT IN('released','in_progress','completed') THEN RAISE EXCEPTION 'Procedure payment has not been released'; END IF;
 END IF;
 INSERT INTO public.procedure_notes(facility_id,patient_id,procedure_name,template_used,indication,technique,findings,complications,post_op_plan,performed_by,status,charge_amount,service_order_id)
 VALUES(pf,_patient_id,NULLIF(pg_catalog.btrim(_procedure_name),''),NULLIF(pg_catalog.btrim(_template_used),''),NULLIF(pg_catalog.btrim(_indication),''),NULLIF(pg_catalog.btrim(_technique),''),NULLIF(pg_catalog.btrim(_findings),''),NULLIF(pg_catalog.btrim(_complications),''),NULLIF(pg_catalog.btrim(_post_op_plan),''),uid,'completed',COALESCE(_charge_amount,0),_service_order_id) RETURNING id INTO v_id;
 RETURN v_id;
END;$function$;

CREATE OR REPLACE FUNCTION public.create_theatre_case(_patient_id uuid,_procedure_name text,_scheduled_start timestamptz DEFAULT NULL,_theatre_name text DEFAULT NULL,_urgency text DEFAULT 'elective',_surgeon_id uuid DEFAULT NULL,_anesthetist_id uuid DEFAULT NULL,_encounter_id uuid DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
DECLARE uid uuid:=auth.uid(); ep uuid; es text; v_id uuid; pf uuid;
BEGIN
 IF uid IS NULL OR NOT(public.has_role(uid,'admin') OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse') OR public.has_role(uid,'specialist_nurse')) THEN RAISE EXCEPTION 'Theatre clinical role required'; END IF;
 IF _patient_id IS NULL OR NULLIF(pg_catalog.btrim(_procedure_name),'') IS NULL THEN RAISE EXCEPTION 'Patient and procedure are required'; END IF;
 pf:=public.assert_patient_facility_context(_patient_id);
 IF _encounter_id IS NOT NULL THEN SELECT patient_id,status INTO ep,es FROM public.encounters WHERE id=_encounter_id AND facility_id=pf; IF NOT FOUND OR ep<>_patient_id THEN RAISE EXCEPTION 'Encounter does not belong to patient facility'; END IF; IF es IN('completed','cancelled') THEN RAISE EXCEPTION 'Cannot create theatre case for a closed encounter'; END IF; END IF;
 IF _surgeon_id IS NOT NULL AND NOT public.has_role(_surgeon_id,'practitioner') THEN RAISE EXCEPTION 'Assigned surgeon must be a practitioner'; END IF;
 IF _anesthetist_id IS NOT NULL AND NOT public.has_role(_anesthetist_id,'practitioner') THEN RAISE EXCEPTION 'Assigned anesthetist must be a practitioner'; END IF;
 INSERT INTO public.theatre_cases(facility_id,patient_id,encounter_id,procedure_name,surgeon_id,anesthetist_id,scheduled_start,theatre_name,urgency,status,created_by)
 VALUES(pf,_patient_id,_encounter_id,pg_catalog.btrim(_procedure_name),_surgeon_id,_anesthetist_id,_scheduled_start,NULLIF(pg_catalog.btrim(_theatre_name),''),COALESCE(NULLIF(pg_catalog.btrim(_urgency),''),'elective'),'requested',uid) RETURNING id INTO v_id;
 RETURN v_id;
END;$function$;

CREATE OR REPLACE FUNCTION public.create_transfusion_record(_patient_id uuid,_blood_product text,_unit_identifier text,_blood_group text DEFAULT NULL,_consent_confirmed boolean DEFAULT false,_encounter_id uuid DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
DECLARE uid uuid:=auth.uid(); v_id uuid; v_patient uuid; v_status text; pf uuid;
BEGIN
 IF uid IS NULL OR NOT(public.has_role(uid,'admin') OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse') OR public.has_role(uid,'midwife') OR public.has_role(uid,'specialist_nurse')) THEN RAISE EXCEPTION 'Clinical role required'; END IF;
 IF _patient_id IS NULL OR NULLIF(pg_catalog.btrim(_blood_product),'') IS NULL OR NULLIF(pg_catalog.btrim(_unit_identifier),'') IS NULL THEN RAISE EXCEPTION 'Patient, blood product and unit identifier are required'; END IF;
 pf:=public.assert_patient_facility_context(_patient_id);
 IF _consent_confirmed IS NOT TRUE THEN RAISE EXCEPTION 'Documented transfusion consent must be confirmed before scheduling'; END IF;
 IF _encounter_id IS NOT NULL THEN SELECT patient_id,status INTO v_patient,v_status FROM public.encounters WHERE id=_encounter_id AND facility_id=pf FOR UPDATE; IF NOT FOUND OR v_patient<>_patient_id THEN RAISE EXCEPTION 'Encounter does not belong to the selected patient facility'; END IF; IF v_status IN('completed','cancelled') THEN RAISE EXCEPTION 'Cannot schedule transfusion for a completed or cancelled encounter'; END IF; END IF;
 IF EXISTS(SELECT 1 FROM public.transfusion_records WHERE unit_identifier=NULLIF(pg_catalog.btrim(_unit_identifier),'') AND status NOT IN('cancelled')) THEN RAISE EXCEPTION 'Blood unit is already assigned to an active transfusion record'; END IF;
 INSERT INTO public.transfusion_records(facility_id,patient_id,blood_group,component,unit_identifier,consent_confirmed,status,encounter_id)
 VALUES(pf,_patient_id,NULLIF(pg_catalog.btrim(COALESCE(_blood_group,'')),''),pg_catalog.btrim(_blood_product),pg_catalog.btrim(_unit_identifier),true,'issued',_encounter_id) RETURNING id INTO v_id;
 RETURN v_id;
END;$function$;

REVOKE ALL ON FUNCTION public.create_nursing_note(uuid,text,text,text,text,text,uuid,uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_nursing_note(uuid,text,text,text,text,text,uuid,uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.create_nursing_note(uuid,text,text,text,text,text,uuid,uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.create_ophthalmology_exam(uuid,text,text,text,numeric,text,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_ophthalmology_exam(uuid,text,text,text,numeric,text,text) FROM anon;
GRANT EXECUTE ON FUNCTION public.create_ophthalmology_exam(uuid,text,text,text,numeric,text,text) TO authenticated;
REVOKE ALL ON FUNCTION public.create_procedure_note(uuid,text,text,text,text,text,text,text,numeric,uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_procedure_note(uuid,text,text,text,text,text,text,text,numeric,uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.create_procedure_note(uuid,text,text,text,text,text,text,text,numeric,uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.create_theatre_case(uuid,text,timestamptz,text,text,uuid,uuid,uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_theatre_case(uuid,text,timestamptz,text,text,uuid,uuid,uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.create_theatre_case(uuid,text,timestamptz,text,text,uuid,uuid,uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.create_transfusion_record(uuid,text,text,text,boolean,uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_transfusion_record(uuid,text,text,text,boolean,uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.create_transfusion_record(uuid,text,text,text,boolean,uuid) TO authenticated;
