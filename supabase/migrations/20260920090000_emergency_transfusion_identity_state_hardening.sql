-- Harden emergency and transfusion lifecycle identity/state boundaries.
CREATE OR REPLACE FUNCTION public.transition_emergency_case(_case_id UUID,_status TEXT,_disposition TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE uid UUID:=auth.uid(); c public.emergency_cases%ROWTYPE; es TEXT;
BEGIN
 IF uid IS NULL OR NOT(public.has_role(uid,'admin') OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse') OR public.has_role(uid,'midwife') OR public.has_role(uid,'specialist_nurse')) THEN RAISE EXCEPTION 'Clinical role required'; END IF;
 IF _status NOT IN('waiting','triage','treatment','observation','admitted','discharged','referred','left_without_being_seen','cancelled') THEN RAISE EXCEPTION 'Invalid emergency status'; END IF;
 SELECT * INTO c FROM public.emergency_cases WHERE id=_case_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Emergency case not found'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.patients WHERE id=c.patient_id) THEN RAISE EXCEPTION 'Emergency patient not found'; END IF;
 IF c.status IN('discharged','referred','left_without_being_seen','cancelled') AND _status<>c.status THEN RAISE EXCEPTION 'Closed emergency case cannot be reopened'; END IF;
 IF c.status='waiting' AND _status NOT IN('waiting','triage','cancelled','left_without_being_seen') THEN RAISE EXCEPTION 'Emergency case must be triaged before treatment'; END IF;
 IF c.status='triage' AND _status NOT IN('triage','treatment','observation','admitted','referred','cancelled') THEN RAISE EXCEPTION 'Invalid emergency transition from triage'; END IF;
 IF _status IN('discharged','referred','left_without_being_seen','cancelled') AND NULLIF(btrim(COALESCE(_disposition,'')),'') IS NULL THEN RAISE EXCEPTION 'Disposition is required when closing an emergency case'; END IF;
 UPDATE public.emergency_cases SET status=_status,disposition=COALESCE(NULLIF(btrim(_disposition),''),disposition),assigned_officer=COALESCE(assigned_officer,uid),updated_at=now() WHERE id=c.id;
 PERFORM public.record_system_audit('emergency_case_transition','emergency','emergency_case',c.id,'info',jsonb_build_object('patient_id',c.patient_id,'from_status',c.status,'to_status',_status,'disposition',_disposition));
 RETURN jsonb_build_object('case_id',c.id,'status',_status);
END; $$;

CREATE OR REPLACE FUNCTION public.create_transfusion_record(_patient_id UUID,_blood_product TEXT,_unit_identifier TEXT,_blood_group TEXT DEFAULT NULL,_consent_confirmed BOOLEAN DEFAULT FALSE,_encounter_id UUID DEFAULT NULL)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE uid UUID:=auth.uid(); v_id UUID; v_patient UUID; v_status TEXT;
BEGIN
 IF uid IS NULL OR NOT(public.has_role(uid,'admin') OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse') OR public.has_role(uid,'midwife') OR public.has_role(uid,'specialist_nurse')) THEN RAISE EXCEPTION 'Clinical role required'; END IF;
 IF _patient_id IS NULL OR NULLIF(btrim(_blood_product),'') IS NULL OR NULLIF(btrim(_unit_identifier),'') IS NULL THEN RAISE EXCEPTION 'Patient, blood product and unit identifier are required'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.patients WHERE id=_patient_id) THEN RAISE EXCEPTION 'Patient not found'; END IF;
 IF _consent_confirmed IS NOT TRUE THEN RAISE EXCEPTION 'Documented transfusion consent must be confirmed before scheduling'; END IF;
 IF _encounter_id IS NOT NULL THEN
   SELECT patient_id,status INTO v_patient,v_status FROM public.encounters WHERE id=_encounter_id FOR UPDATE;
   IF NOT FOUND OR v_patient<>_patient_id THEN RAISE EXCEPTION 'Encounter does not belong to the selected patient'; END IF;
   IF v_status IN('completed','cancelled') THEN RAISE EXCEPTION 'Cannot schedule transfusion for a completed or cancelled encounter'; END IF;
 END IF;
 IF EXISTS(SELECT 1 FROM public.transfusion_records WHERE unit_identifier=NULLIF(btrim(_unit_identifier),'') AND status NOT IN('cancelled')) THEN RAISE EXCEPTION 'Blood unit is already assigned to an active transfusion record'; END IF;
 INSERT INTO public.transfusion_records(patient_id,blood_group,component,unit_identifier,consent_confirmed,status,encounter_id)
 VALUES(_patient_id,NULLIF(btrim(COALESCE(_blood_group,'')),''),btrim(_blood_product),btrim(_unit_identifier),true,'issued',_encounter_id) RETURNING id INTO v_id;
 RETURN v_id;
END; $$;

REVOKE ALL ON FUNCTION public.transition_emergency_case(UUID,TEXT,TEXT) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.create_transfusion_record(UUID,TEXT,TEXT,TEXT,BOOLEAN,UUID) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.transition_emergency_case(UUID,TEXT,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_transfusion_record(UUID,TEXT,TEXT,TEXT,BOOLEAN,UUID) TO authenticated;
