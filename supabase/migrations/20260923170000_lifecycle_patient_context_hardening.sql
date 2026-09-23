-- Enforce active-patient context across emergency, theatre and transfusion lifecycle transitions.

CREATE OR REPLACE FUNCTION public.transition_emergency_case(_case_id UUID,_status TEXT,_disposition TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE uid UUID:=auth.uid(); c public.emergency_cases%ROWTYPE;
BEGIN
 IF uid IS NULL OR NOT(public.has_role(uid,'admin') OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse') OR public.has_role(uid,'midwife') OR public.has_role(uid,'specialist_nurse')) THEN RAISE EXCEPTION 'Clinical role required'; END IF;
 IF _status NOT IN('waiting','triage','treatment','observation','admitted','discharged','referred','left_without_being_seen','cancelled') THEN RAISE EXCEPTION 'Invalid emergency status'; END IF;
 SELECT * INTO c FROM public.emergency_cases WHERE id=_case_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Emergency case not found'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.patients WHERE id=c.patient_id AND COALESCE(status,'active')<>'inactive') THEN RAISE EXCEPTION 'Emergency patient not found or inactive'; END IF;
 IF c.status IN('discharged','referred','left_without_being_seen','cancelled') AND _status<>c.status THEN RAISE EXCEPTION 'Closed emergency case cannot be reopened'; END IF;
 IF c.status='waiting' AND _status NOT IN('waiting','triage','cancelled','left_without_being_seen') THEN RAISE EXCEPTION 'Emergency case must be triaged before treatment'; END IF;
 IF c.status='triage' AND _status NOT IN('triage','treatment','observation','admitted','referred','cancelled') THEN RAISE EXCEPTION 'Invalid emergency transition from triage'; END IF;
 IF _status IN('discharged','referred','left_without_being_seen','cancelled') AND NULLIF(btrim(COALESCE(_disposition,'')),'') IS NULL THEN RAISE EXCEPTION 'Disposition is required when closing an emergency case'; END IF;
 UPDATE public.emergency_cases SET status=_status,disposition=COALESCE(NULLIF(btrim(_disposition),''),disposition),assigned_officer=COALESCE(assigned_officer,uid),updated_at=now() WHERE id=c.id;
 PERFORM public.record_system_audit('emergency_case_transition','emergency','emergency_case',c.id,'info',jsonb_build_object('patient_id',c.patient_id,'from_status',c.status,'to_status',_status,'disposition',_disposition));
 RETURN jsonb_build_object('case_id',c.id,'status',_status);
END; $$;

CREATE OR REPLACE FUNCTION public.transition_theatre_case(_case_id UUID,_status TEXT,_cancellation_reason TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE uid UUID:=auth.uid(); c public.theatre_cases%ROWTYPE; es TEXT; allowed BOOLEAN:=false;
BEGIN
 IF uid IS NULL OR NOT(public.has_role(uid,'admin') OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse') OR public.has_role(uid,'midwife')) THEN RAISE EXCEPTION 'Clinical role required'; END IF;
 IF _status NOT IN('requested','approved','scheduled','in_progress','completed','cancelled','postponed') THEN RAISE EXCEPTION 'Invalid theatre status'; END IF;
 SELECT * INTO c FROM public.theatre_cases WHERE id=_case_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Theatre case not found'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.patients WHERE id=c.patient_id AND COALESCE(status,'active')<>'inactive') THEN RAISE EXCEPTION 'Theatre patient not found or inactive'; END IF;
 IF c.status IN('completed','cancelled') AND _status<>c.status THEN RAISE EXCEPTION 'Closed theatre case cannot be reopened'; END IF;
 IF c.encounter_id IS NOT NULL THEN
   SELECT status INTO es FROM public.encounters WHERE id=c.encounter_id;
   IF NOT FOUND THEN RAISE EXCEPTION 'Linked encounter not found'; END IF;
   IF es IN('completed','cancelled') AND _status NOT IN('completed','cancelled') THEN RAISE EXCEPTION 'Cannot modify theatre case for a closed encounter'; END IF;
 END IF;
 allowed:=(_status='approved' AND c.status='requested') OR (_status='scheduled' AND c.status='approved') OR (_status='in_progress' AND c.status='scheduled') OR (_status='completed' AND c.status='in_progress') OR (_status='cancelled' AND c.status IN('requested','approved','scheduled','postponed')) OR (_status='postponed' AND c.status IN('requested','approved','scheduled'));
 IF NOT allowed AND _status<>c.status THEN RAISE EXCEPTION 'Invalid theatre lifecycle transition'; END IF;
 IF _status IN('cancelled','postponed') AND NULLIF(btrim(COALESCE(_cancellation_reason,'')),'') IS NULL THEN RAISE EXCEPTION 'A reason is required for cancellation or postponement'; END IF;
 UPDATE public.theatre_cases SET status=_status,notes=CASE WHEN _status IN('cancelled','postponed') THEN NULLIF(btrim(_cancellation_reason),'') ELSE notes END,updated_at=now() WHERE id=c.id;
 RETURN jsonb_build_object('case_id',c.id,'status',_status);
END; $$;

CREATE OR REPLACE FUNCTION public.record_transfusion_event(_record_id UUID,_status TEXT,_reaction_observed BOOLEAN DEFAULT false,_reaction_notes TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE uid UUID:=auth.uid(); r public.transfusion_records%ROWTYPE; es TEXT; allowed BOOLEAN:=false;
BEGIN
 IF uid IS NULL OR NOT(public.has_role(uid,'admin') OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse') OR public.has_role(uid,'midwife')) THEN RAISE EXCEPTION 'Clinical role required'; END IF;
 IF _status NOT IN('issued','running','completed','stopped','cancelled') THEN RAISE EXCEPTION 'Invalid transfusion status'; END IF;
 SELECT * INTO r FROM public.transfusion_records WHERE id=_record_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Transfusion record not found'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.patients WHERE id=r.patient_id AND COALESCE(status,'active')<>'inactive') THEN RAISE EXCEPTION 'Transfusion patient not found or inactive'; END IF;
 IF r.status IN('completed','stopped','cancelled') AND _status<>r.status THEN RAISE EXCEPTION 'Closed transfusion record cannot be reopened'; END IF;
 IF r.status='issued' AND _status IN('running','cancelled') THEN allowed:=true;
 ELSIF r.status='running' AND _status IN('completed','stopped','cancelled') THEN allowed:=true;
 ELSIF _status=r.status THEN allowed:=true; END IF;
 IF NOT allowed THEN RAISE EXCEPTION 'Invalid transfusion lifecycle transition'; END IF;
 IF r.encounter_id IS NOT NULL THEN
   SELECT status INTO es FROM public.encounters WHERE id=r.encounter_id;
   IF NOT FOUND THEN RAISE EXCEPTION 'Linked encounter not found'; END IF;
   IF es='cancelled' OR (es='completed' AND _status NOT IN('completed','stopped','cancelled')) THEN RAISE EXCEPTION 'Cannot change transfusion lifecycle for a closed encounter'; END IF;
 END IF;
 IF _status IN('running','completed') AND r.compatibility_checked IS NOT TRUE THEN RAISE EXCEPTION 'Transfusion must be independently verified before administration'; END IF;
 UPDATE public.transfusion_records SET status=_status,reaction_observed=COALESCE(_reaction_observed,false),reaction_notes=CASE WHEN COALESCE(_reaction_observed,false) THEN NULLIF(btrim(_reaction_notes),'') ELSE reaction_notes END,started_at=CASE WHEN _status='running' AND started_at IS NULL THEN now() ELSE started_at END,completed_at=CASE WHEN _status IN('completed','stopped') THEN COALESCE(completed_at,now()) ELSE completed_at END,administered_by=COALESCE(administered_by,uid),updated_at=now() WHERE id=r.id;
 RETURN jsonb_build_object('record_id',r.id,'status',_status,'reaction_observed',COALESCE(_reaction_observed,false));
END; $$;

REVOKE ALL ON FUNCTION public.transition_emergency_case(UUID,TEXT,TEXT) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.transition_theatre_case(UUID,TEXT,TEXT) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.record_transfusion_event(UUID,TEXT,BOOLEAN,TEXT) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.transition_emergency_case(UUID,TEXT,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.transition_theatre_case(UUID,TEXT,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_transfusion_event(UUID,TEXT,BOOLEAN,TEXT) TO authenticated;
