-- Gate A: harden legacy five-argument prescription overload with the same test-mode-first boundary.
CREATE OR REPLACE FUNCTION public.create_encounter_prescription(_encounter_id uuid,_medication text,_dosage text DEFAULT NULL,_frequency text DEFAULT NULL,_duration text DEFAULT NULL)
RETURNS public.prescriptions LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $function$
DECLARE uid uuid:=auth.uid(); v_encounter public.encounters%ROWTYPE; v_patient_facility uuid; result public.prescriptions;
BEGIN
 IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 IF NOT(public.has_role(uid,'admin') OR public.has_role(uid,'it_admin') OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse') OR public.has_role(uid,'midwife') OR public.has_role(uid,'specialist_nurse')) THEN RAISE EXCEPTION 'Not authorized to prescribe'; END IF;
 SELECT * INTO v_encounter FROM public.encounters WHERE id=_encounter_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Encounter does not exist'; END IF;
 SELECT facility_id INTO v_patient_facility FROM public.patients WHERE id=v_encounter.patient_id FOR SHARE;
 IF v_encounter.facility_id IS NULL OR v_patient_facility IS NULL THEN RAISE EXCEPTION 'Encounter or patient facility attribution is unresolved'; END IF;
 IF public.hms_test_mode_enabled() THEN
  IF v_encounter.facility_id IS DISTINCT FROM public.hms_test_facility_id() OR v_patient_facility IS DISTINCT FROM public.hms_test_facility_id() THEN RAISE EXCEPTION 'Test mode permits prescriptions only within TEST-0001'; END IF;
 ELSE
  IF NOT(public.has_role(uid,'admin') OR public.has_role(uid,'it_admin')) AND (public.current_user_facility_id() IS NULL OR v_encounter.facility_id IS DISTINCT FROM public.current_user_facility_id() OR v_patient_facility IS DISTINCT FROM public.current_user_facility_id()) THEN RAISE EXCEPTION 'Encounter belongs to a different facility context'; END IF;
 END IF;
 IF v_encounter.status IN('completed','cancelled') THEN RAISE EXCEPTION 'Completed or cancelled encounters are read-only'; END IF;
 IF NULLIF(pg_catalog.btrim(_medication),'') IS NULL THEN RAISE EXCEPTION 'Medication is required'; END IF;
 INSERT INTO public.prescriptions(encounter_id,patient_id,prescribed_by,medication,dosage,frequency,duration,facility_id)
 VALUES(v_encounter.id,v_encounter.patient_id,uid,pg_catalog.btrim(_medication),NULLIF(pg_catalog.btrim(_dosage),''),NULLIF(pg_catalog.btrim(_frequency),''),NULLIF(pg_catalog.btrim(_duration),''),v_encounter.facility_id)
 RETURNING * INTO result;
 RETURN result;
END;$function$;
REVOKE ALL ON FUNCTION public.create_encounter_prescription(uuid,text,text,text,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.create_encounter_prescription(uuid,text,text,text,text) TO authenticated;
NOTIFY pgrst,'reload schema';