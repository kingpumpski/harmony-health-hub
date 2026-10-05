-- Gate A: diagnosis lifecycle facility boundary.
CREATE OR REPLACE FUNCTION public.set_principal_diagnosis(_encounter_id uuid,_diagnosis_id uuid)
RETURNS public.diagnoses LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $function$
DECLARE uid uuid:=auth.uid(); result public.diagnoses; v_enc public.encounters; v_patient_facility uuid;
BEGIN
 IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 IF NOT(public.has_role(uid,'admin') OR public.has_role(uid,'it_admin') OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse') OR public.has_role(uid,'midwife') OR public.has_role(uid,'specialist_nurse')) THEN RAISE EXCEPTION 'Not authorized to set principal diagnosis'; END IF;
 SELECT * INTO v_enc FROM public.encounters WHERE id=_encounter_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Encounter does not exist'; END IF;
 SELECT facility_id INTO v_patient_facility FROM public.patients WHERE id=v_enc.patient_id FOR SHARE;
 IF v_enc.facility_id IS NULL OR v_patient_facility IS NULL THEN RAISE EXCEPTION 'Encounter or patient facility attribution is unresolved'; END IF;
 IF public.hms_test_mode_enabled() THEN
  IF v_enc.facility_id IS DISTINCT FROM public.hms_test_facility_id() OR v_patient_facility IS DISTINCT FROM public.hms_test_facility_id() THEN RAISE EXCEPTION 'Test mode permits diagnosis changes only within TEST-0001'; END IF;
 ELSE
  IF NOT(public.has_role(uid,'admin') OR public.has_role(uid,'it_admin')) AND (public.current_user_facility_id() IS NULL OR v_enc.facility_id IS DISTINCT FROM public.current_user_facility_id() OR v_patient_facility IS DISTINCT FROM public.current_user_facility_id()) THEN RAISE EXCEPTION 'Encounter belongs to a different facility context'; END IF;
 END IF;
 IF v_enc.status IN('completed','cancelled') THEN RAISE EXCEPTION 'Completed or cancelled encounters are read-only'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.diagnoses WHERE id=_diagnosis_id AND encounter_id=_encounter_id AND (facility_id=v_enc.facility_id OR facility_id IS NULL)) THEN RAISE EXCEPTION 'Diagnosis does not belong to encounter'; END IF;
 UPDATE public.diagnoses SET is_principal=false WHERE encounter_id=_encounter_id;
 UPDATE public.diagnoses SET is_principal=true WHERE id=_diagnosis_id RETURNING * INTO result;
 UPDATE public.encounters SET principal_diagnosis=result.diagnosis,updated_at=pg_catalog.now() WHERE id=_encounter_id;
 RETURN result;
END;$function$;
CREATE OR REPLACE FUNCTION public.remove_encounter_diagnosis(_diagnosis_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $function$
DECLARE uid uuid:=auth.uid(); v_enc public.encounters; v_diag public.diagnoses; v_patient_facility uuid;
BEGIN
 IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 IF NOT(public.has_role(uid,'admin') OR public.has_role(uid,'it_admin') OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse') OR public.has_role(uid,'midwife') OR public.has_role(uid,'specialist_nurse')) THEN RAISE EXCEPTION 'Not authorized to remove diagnoses'; END IF;
 SELECT * INTO v_diag FROM public.diagnoses WHERE id=_diagnosis_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Diagnosis does not exist'; END IF;
 SELECT * INTO v_enc FROM public.encounters WHERE id=v_diag.encounter_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Encounter does not exist'; END IF;
 SELECT facility_id INTO v_patient_facility FROM public.patients WHERE id=v_enc.patient_id FOR SHARE;
 IF v_enc.facility_id IS NULL OR v_patient_facility IS NULL THEN RAISE EXCEPTION 'Encounter or patient facility attribution is unresolved'; END IF;
 IF public.hms_test_mode_enabled() THEN
  IF v_enc.facility_id IS DISTINCT FROM public.hms_test_facility_id() OR v_patient_facility IS DISTINCT FROM public.hms_test_facility_id() THEN RAISE EXCEPTION 'Test mode permits diagnosis changes only within TEST-0001'; END IF;
 ELSE
  IF NOT(public.has_role(uid,'admin') OR public.has_role(uid,'it_admin')) AND (public.current_user_facility_id() IS NULL OR v_enc.facility_id IS DISTINCT FROM public.current_user_facility_id() OR v_patient_facility IS DISTINCT FROM public.current_user_facility_id()) THEN RAISE EXCEPTION 'Encounter belongs to a different facility context'; END IF;
 END IF;
 IF v_diag.facility_id IS NOT NULL AND v_diag.facility_id IS DISTINCT FROM v_enc.facility_id THEN RAISE EXCEPTION 'Diagnosis belongs to a different facility context'; END IF;
 IF v_enc.status IN('completed','cancelled') THEN RAISE EXCEPTION 'Completed or cancelled encounters are read-only'; END IF;
 IF v_diag.is_principal THEN RAISE EXCEPTION 'Principal diagnosis cannot be removed; assign another principal diagnosis first'; END IF;
 DELETE FROM public.diagnoses WHERE id=_diagnosis_id;
END;$function$;
REVOKE ALL ON FUNCTION public.set_principal_diagnosis(uuid,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.set_principal_diagnosis(uuid,uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.remove_encounter_diagnosis(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.remove_encounter_diagnosis(uuid) TO authenticated;
NOTIFY pgrst,'reload schema';