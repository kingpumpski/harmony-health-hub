-- Reconcile Clinical Operations lifecycle RPC roles with the merged workspace boundary.
-- Preserve the existing production lifecycle/security invariants and change only the
-- server-side role predicates needed to match the merged workspace boundary.

CREATE OR REPLACE FUNCTION public.create_theatre_case(_patient_id uuid, _procedure_name text, _scheduled_start timestamp with time zone DEFAULT NULL::timestamp with time zone, _theatre_name text DEFAULT NULL::text, _urgency text DEFAULT 'elective'::text, _surgeon_id uuid DEFAULT NULL::uuid, _anesthetist_id uuid DEFAULT NULL::uuid, _encounter_id uuid DEFAULT NULL::uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE uid UUID:=auth.uid(); ep UUID; es TEXT; id UUID;
BEGIN
 IF uid IS NULL OR NOT(public.has_role(uid,'admin') OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse') OR public.has_role(uid,'specialist_nurse')) THEN RAISE EXCEPTION 'Theatre clinical role required'; END IF;
 IF _patient_id IS NULL OR NULLIF(btrim(_procedure_name),'') IS NULL THEN RAISE EXCEPTION 'Patient and procedure are required'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.patients WHERE id=_patient_id) THEN RAISE EXCEPTION 'Patient not found'; END IF;
 IF _encounter_id IS NOT NULL THEN
   SELECT patient_id,status INTO ep,es FROM public.encounters WHERE id=_encounter_id;
   IF NOT FOUND OR ep<>_patient_id THEN RAISE EXCEPTION 'Encounter does not belong to patient'; END IF;
   IF es IN('completed','cancelled') THEN RAISE EXCEPTION 'Cannot create theatre case for a closed encounter'; END IF;
 END IF;
 IF _surgeon_id IS NOT NULL AND NOT public.has_role(_surgeon_id,'practitioner') THEN RAISE EXCEPTION 'Assigned surgeon must be a practitioner'; END IF;
 IF _anesthetist_id IS NOT NULL AND NOT(public.has_role(_anesthetist_id,'practitioner')) THEN RAISE EXCEPTION 'Assigned anesthetist must be a practitioner'; END IF;
 INSERT INTO public.theatre_cases(patient_id,encounter_id,procedure_name,surgeon_id,anesthetist_id,scheduled_start,theatre_name,urgency,status,created_by)
 VALUES(_patient_id,_encounter_id,btrim(_procedure_name),_surgeon_id,_anesthetist_id,_scheduled_start,NULLIF(btrim(_theatre_name),''),COALESCE(NULLIF(btrim(_urgency),''),'elective'),'requested',uid)
 RETURNING id INTO id;
 RETURN id;
END; $function$;

CREATE OR REPLACE FUNCTION public.transition_theatre_case(_case_id uuid, _status text, _cancellation_reason text DEFAULT NULL::text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE uid UUID:=auth.uid(); c public.theatre_cases%ROWTYPE; es TEXT; allowed BOOLEAN:=false;
BEGIN
 IF uid IS NULL OR NOT(public.has_role(uid,'admin') OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse') OR public.has_role(uid,'specialist_nurse')) THEN RAISE EXCEPTION 'Clinical role required'; END IF;
 IF _status NOT IN('requested','approved','scheduled','in_progress','completed','cancelled','postponed') THEN RAISE EXCEPTION 'Invalid theatre status'; END IF;
 SELECT * INTO c FROM public.theatre_cases WHERE id=_case_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Theatre case not found'; END IF;
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
END; $function$;

CREATE OR REPLACE FUNCTION public.create_transfusion_record(_patient_id uuid, _blood_product text, _unit_identifier text, _blood_group text DEFAULT NULL::text, _consent_confirmed boolean DEFAULT false, _encounter_id uuid DEFAULT NULL::uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
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
END; $function$;

CREATE OR REPLACE FUNCTION public.record_transfusion_event(_record_id uuid, _status text, _reaction_observed boolean DEFAULT false, _reaction_notes text DEFAULT NULL::text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE uid UUID:=auth.uid(); r public.transfusion_records%ROWTYPE; es TEXT; allowed BOOLEAN:=false;
BEGIN
 IF uid IS NULL OR NOT(public.has_role(uid,'admin') OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse') OR public.has_role(uid,'midwife') OR public.has_role(uid,'specialist_nurse')) THEN RAISE EXCEPTION 'Clinical role required'; END IF;
 IF _status NOT IN('issued','running','completed','stopped','cancelled') THEN RAISE EXCEPTION 'Invalid transfusion status'; END IF;
 SELECT * INTO r FROM public.transfusion_records WHERE id=_record_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Transfusion record not found'; END IF;
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
END; $function$;

REVOKE ALL ON FUNCTION public.create_theatre_case(uuid,text,timestamptz,text,text,uuid,uuid,uuid) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.transition_theatre_case(uuid,text,text) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.create_transfusion_record(uuid,text,text,text,boolean,uuid) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.record_transfusion_event(uuid,text,boolean,text) FROM PUBLIC,anon;

GRANT EXECUTE ON FUNCTION public.create_theatre_case(uuid,text,timestamptz,text,text,uuid,uuid,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.transition_theatre_case(uuid,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_transfusion_record(uuid,text,text,text,boolean,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_transfusion_event(uuid,text,boolean,text) TO authenticated;
