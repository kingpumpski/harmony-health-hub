-- Gate A: harden encounter draft, completion, and prescription writes with test-mode-first facility enforcement.
CREATE OR REPLACE FUNCTION public.save_encounter_draft(_encounter_id uuid,_symptoms text DEFAULT NULL,_clerking_notes text DEFAULT NULL,_treatment_plan text DEFAULT NULL)
RETURNS public.encounters LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $function$
DECLARE uid uuid:=auth.uid(); v public.encounters; v_patient_facility uuid;
BEGIN
 IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 IF NOT(public.has_role(uid,'admin') OR public.has_role(uid,'it_admin') OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse') OR public.has_role(uid,'midwife') OR public.has_role(uid,'specialist_nurse')) THEN RAISE EXCEPTION 'Not authorized to save encounter draft'; END IF;
 SELECT * INTO v FROM public.encounters WHERE id=_encounter_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Encounter not found'; END IF;
 SELECT facility_id INTO v_patient_facility FROM public.patients WHERE id=v.patient_id FOR SHARE;
 IF v.facility_id IS NULL OR v_patient_facility IS NULL THEN RAISE EXCEPTION 'Encounter or patient facility attribution is unresolved'; END IF;
 IF public.hms_test_mode_enabled() THEN
  IF v.facility_id IS DISTINCT FROM public.hms_test_facility_id() OR v_patient_facility IS DISTINCT FROM public.hms_test_facility_id() THEN RAISE EXCEPTION 'Test mode permits encounter editing only within TEST-0001'; END IF;
 ELSE
  IF NOT(public.has_role(uid,'admin') OR public.has_role(uid,'it_admin')) AND (public.current_user_facility_id() IS NULL OR v.facility_id IS DISTINCT FROM public.current_user_facility_id() OR v_patient_facility IS DISTINCT FROM public.current_user_facility_id()) THEN RAISE EXCEPTION 'Encounter belongs to a different facility context'; END IF;
 END IF;
 IF v.practitioner_id<>uid AND NOT(public.has_role(uid,'admin') OR public.has_role(uid,'it_admin')) THEN RAISE EXCEPTION 'Only the encounter creator or an administrator may save this draft'; END IF;
 IF v.status<>'draft' THEN RAISE EXCEPTION 'Only draft encounters can be edited'; END IF;
 UPDATE public.encounters SET symptoms=NULLIF(pg_catalog.btrim(_symptoms),''),clerking_notes=NULLIF(pg_catalog.btrim(_clerking_notes),''),treatment_plan=NULLIF(pg_catalog.btrim(_treatment_plan),''),updated_at=pg_catalog.now() WHERE id=_encounter_id RETURNING * INTO v;
 RETURN v;
END;$function$;

CREATE OR REPLACE FUNCTION public.complete_encounter_workflow(_encounter_id uuid)
RETURNS public.encounters LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $function$
DECLARE uid uuid:=auth.uid(); v public.encounters; v_patient_facility uuid;
BEGIN
 IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 IF NOT(public.has_role(uid,'admin') OR public.has_role(uid,'it_admin') OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse') OR public.has_role(uid,'midwife') OR public.has_role(uid,'specialist_nurse')) THEN RAISE EXCEPTION 'Not authorized to complete encounters'; END IF;
 SELECT * INTO v FROM public.encounters WHERE id=_encounter_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Encounter does not exist'; END IF;
 SELECT facility_id INTO v_patient_facility FROM public.patients WHERE id=v.patient_id FOR SHARE;
 IF v.facility_id IS NULL OR v_patient_facility IS NULL THEN RAISE EXCEPTION 'Encounter or patient facility attribution is unresolved'; END IF;
 IF public.hms_test_mode_enabled() THEN
  IF v.facility_id IS DISTINCT FROM public.hms_test_facility_id() OR v_patient_facility IS DISTINCT FROM public.hms_test_facility_id() THEN RAISE EXCEPTION 'Test mode permits encounter completion only within TEST-0001'; END IF;
 ELSE
  IF NOT(public.has_role(uid,'admin') OR public.has_role(uid,'it_admin')) AND (public.current_user_facility_id() IS NULL OR v.facility_id IS DISTINCT FROM public.current_user_facility_id() OR v_patient_facility IS DISTINCT FROM public.current_user_facility_id()) THEN RAISE EXCEPTION 'Encounter belongs to a different facility context'; END IF;
 END IF;
 IF v.status IN('completed','cancelled') THEN RAISE EXCEPTION 'Encounter is already closed'; END IF;
 IF v.practitioner_id<>uid AND NOT(public.has_role(uid,'admin') OR public.has_role(uid,'it_admin')) THEN RAISE EXCEPTION 'Only the assigned clinician may complete this encounter'; END IF;
 IF v.principal_diagnosis IS NULL OR NULLIF(pg_catalog.btrim(v.principal_diagnosis),'') IS NULL THEN RAISE EXCEPTION 'Principal diagnosis required'; END IF;
 UPDATE public.encounters SET status='completed',completed_at=coalesce(completed_at,pg_catalog.now()),updated_at=pg_catalog.now() WHERE id=_encounter_id RETURNING * INTO v;
 RETURN v;
END;$function$;

CREATE OR REPLACE FUNCTION public.create_encounter_prescription(_encounter_id uuid,_medication text,_dosage text DEFAULT NULL,_frequency text DEFAULT NULL,_duration text DEFAULT NULL,_diagnosis_id uuid DEFAULT NULL)
RETURNS public.prescriptions LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $function$
DECLARE uid uuid:=auth.uid(); v_enc public.encounters%ROWTYPE; v_patient_facility uuid; result public.prescriptions;
BEGIN
 IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 IF NOT(public.has_role(uid,'admin') OR public.has_role(uid,'it_admin') OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse') OR public.has_role(uid,'midwife') OR public.has_role(uid,'specialist_nurse')) THEN RAISE EXCEPTION 'Not authorized to prescribe'; END IF;
 SELECT * INTO v_enc FROM public.encounters WHERE id=_encounter_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Encounter does not exist'; END IF;
 SELECT facility_id INTO v_patient_facility FROM public.patients WHERE id=v_enc.patient_id FOR SHARE;
 IF v_enc.facility_id IS NULL OR v_patient_facility IS NULL THEN RAISE EXCEPTION 'Encounter or patient facility attribution is unresolved'; END IF;
 IF public.hms_test_mode_enabled() THEN
  IF v_enc.facility_id IS DISTINCT FROM public.hms_test_facility_id() OR v_patient_facility IS DISTINCT FROM public.hms_test_facility_id() THEN RAISE EXCEPTION 'Test mode permits prescriptions only within TEST-0001'; END IF;
 ELSE
  IF NOT(public.has_role(uid,'admin') OR public.has_role(uid,'it_admin')) AND (public.current_user_facility_id() IS NULL OR v_enc.facility_id IS DISTINCT FROM public.current_user_facility_id() OR v_patient_facility IS DISTINCT FROM public.current_user_facility_id()) THEN RAISE EXCEPTION 'Encounter belongs to a different facility context'; END IF;
 END IF;
 IF v_enc.status IN('completed','cancelled') THEN RAISE EXCEPTION 'Completed or cancelled encounters are read-only'; END IF;
 IF NULLIF(pg_catalog.btrim(_medication),'') IS NULL THEN RAISE EXCEPTION 'Medication is required'; END IF;
 IF _diagnosis_id IS NULL OR NOT EXISTS(SELECT 1 FROM public.diagnoses d WHERE d.id=_diagnosis_id AND d.encounter_id=_encounter_id AND (d.facility_id=v_enc.facility_id OR d.facility_id IS NULL)) THEN RAISE EXCEPTION 'Selected treatment diagnosis does not belong to this encounter'; END IF;
 INSERT INTO public.prescriptions(encounter_id,patient_id,prescribed_by,medication,dosage,frequency,duration,diagnosis_id,facility_id)
 VALUES(v_enc.id,v_enc.patient_id,uid,pg_catalog.btrim(_medication),NULLIF(pg_catalog.btrim(_dosage),''),NULLIF(pg_catalog.btrim(_frequency),''),NULLIF(pg_catalog.btrim(_duration),''),_diagnosis_id,v_enc.facility_id)
 RETURNING * INTO result;
 RETURN result;
END;$function$;

REVOKE ALL ON FUNCTION public.save_encounter_draft(uuid,text,text,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.save_encounter_draft(uuid,text,text,text) TO authenticated;
REVOKE ALL ON FUNCTION public.complete_encounter_workflow(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.complete_encounter_workflow(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.create_encounter_prescription(uuid,text,text,text,text,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.create_encounter_prescription(uuid,text,text,text,text,uuid) TO authenticated;
NOTIFY pgrst,'reload schema';