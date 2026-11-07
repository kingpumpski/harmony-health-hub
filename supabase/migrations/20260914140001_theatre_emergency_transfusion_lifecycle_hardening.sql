-- Server-authoritative lifecycle boundaries for theatre, emergency and transfusion workflows.
-- Preserve existing RPC contracts while preventing direct authenticated DML bypasses.

ALTER TABLE public.theatre_cases ADD COLUMN IF NOT EXISTS encounter_id uuid;
ALTER TABLE public.transfusion_records ADD COLUMN IF NOT EXISTS encounter_id uuid;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='theatre_cases_encounter_id_fkey') THEN
    ALTER TABLE public.theatre_cases ADD CONSTRAINT theatre_cases_encounter_id_fkey FOREIGN KEY (encounter_id) REFERENCES public.encounters(id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='transfusion_records_encounter_id_fkey') THEN
    ALTER TABLE public.transfusion_records ADD CONSTRAINT transfusion_records_encounter_id_fkey FOREIGN KEY (encounter_id) REFERENCES public.encounters(id);
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.create_theatre_case(_patient_id uuid, _procedure_name text, _scheduled_start timestamptz DEFAULT NULL, _theatre_name text DEFAULT NULL, _urgency text DEFAULT 'elective', _surgeon_id uuid DEFAULT NULL, _anesthetist_id uuid DEFAULT NULL, _encounter_id uuid DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_id uuid; v_patient uuid; v_status text;
BEGIN
  IF auth.uid() IS NULL OR NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife')) THEN RAISE EXCEPTION 'Not authorized to create theatre cases'; END IF;
  IF _patient_id IS NULL OR NULLIF(trim(_procedure_name),'') IS NULL THEN RAISE EXCEPTION 'Patient and procedure are required'; END IF;
  IF _encounter_id IS NOT NULL THEN
    SELECT patient_id,status INTO v_patient,v_status FROM public.encounters WHERE id=_encounter_id;
    IF NOT FOUND OR v_patient<>_patient_id THEN RAISE EXCEPTION 'Encounter does not belong to the selected patient'; END IF;
    IF v_status IN ('completed','cancelled') THEN RAISE EXCEPTION 'Cannot create a theatre case for a completed or cancelled encounter'; END IF;
  END IF;
  INSERT INTO public.theatre_cases(patient_id,procedure_name,surgeon_id,anaesthetist_id,scheduled_at,theatre,status,created_by,encounter_id)
  VALUES (_patient_id,trim(_procedure_name),_surgeon_id,_anesthetist_id,_scheduled_start,NULLIF(trim(COALESCE(_theatre_name,'')),''),COALESCE(NULLIF(trim(_urgency),''),'elective'),auth.uid(),_encounter_id)
  RETURNING id INTO v_id;
  RETURN v_id;
END; $$;

CREATE OR REPLACE FUNCTION public.transition_theatre_case(_case_id uuid, _status text, _cancellation_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE uid uuid:=auth.uid(); c public.theatre_cases%ROWTYPE; encounter_status text;
BEGIN
  IF uid IS NULL OR NOT (public.has_role(uid,'admin') OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse') OR public.has_role(uid,'midwife')) THEN RAISE EXCEPTION 'Clinical role required'; END IF;
  IF _status NOT IN ('requested','approved','scheduled','in_progress','completed','cancelled','postponed') THEN RAISE EXCEPTION 'Invalid theatre status'; END IF;
  SELECT * INTO c FROM public.theatre_cases WHERE id=_case_id FOR UPDATE;
  IF c.id IS NULL THEN RAISE EXCEPTION 'Theatre case not found'; END IF;
  IF c.status IN ('completed','cancelled') AND _status<>c.status THEN RAISE EXCEPTION 'Closed theatre case cannot be reopened'; END IF;
  IF c.encounter_id IS NOT NULL THEN
    SELECT status INTO encounter_status FROM public.encounters WHERE id=c.encounter_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Linked encounter not found'; END IF;
    IF encounter_status IN ('completed','cancelled') AND _status NOT IN ('completed','cancelled') THEN RAISE EXCEPTION 'Cannot modify theatre case for a completed or cancelled encounter'; END IF;
  END IF;
  UPDATE public.theatre_cases SET status=_status,notes=CASE WHEN _status IN ('cancelled','postponed') THEN COALESCE(NULLIF(trim(_cancellation_reason),''),notes) ELSE notes END,updated_at=now() WHERE id=_case_id;
  RETURN jsonb_build_object('case_id',_case_id,'status',_status);
END; $$;

CREATE OR REPLACE FUNCTION public.transition_emergency_case(_case_id uuid, _status text, _disposition text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE uid uuid:=auth.uid(); c public.emergency_cases%ROWTYPE;
BEGIN
  IF uid IS NULL OR NOT (public.has_role(uid,'admin') OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse') OR public.has_role(uid,'midwife')) THEN RAISE EXCEPTION 'Clinical role required'; END IF;
  IF _status NOT IN ('waiting','triage','treatment','observation','admitted','discharged','referred','left_without_being_seen','cancelled') THEN RAISE EXCEPTION 'Invalid emergency status'; END IF;
  SELECT * INTO c FROM public.emergency_cases WHERE id=_case_id FOR UPDATE;
  IF c.id IS NULL THEN RAISE EXCEPTION 'Emergency case not found'; END IF;
  IF c.status IN ('discharged','referred','left_without_being_seen','cancelled') AND _status<>c.status THEN RAISE EXCEPTION 'Closed emergency case cannot be reopened'; END IF;
  UPDATE public.emergency_cases SET status=_status,disposition=COALESCE(NULLIF(trim(_disposition),''),disposition),assigned_officer=COALESCE(assigned_officer,uid),updated_at=now() WHERE id=_case_id;
  RETURN jsonb_build_object('case_id',_case_id,'status',_status);
END; $$;

CREATE OR REPLACE FUNCTION public.create_transfusion_record(_patient_id uuid, _blood_product text, _unit_identifier text, _blood_group text DEFAULT NULL, _consent_confirmed boolean DEFAULT false, _encounter_id uuid DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_id uuid; v_patient uuid; v_status text;
BEGIN
  IF auth.uid() IS NULL OR NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife')) THEN RAISE EXCEPTION 'Not authorized to create transfusion records'; END IF;
  IF _patient_id IS NULL OR NULLIF(trim(_blood_product),'') IS NULL THEN RAISE EXCEPTION 'Patient and blood product are required'; END IF;
  IF _consent_confirmed IS NOT TRUE THEN RAISE EXCEPTION 'Documented transfusion consent must be confirmed before scheduling'; END IF;
  IF _encounter_id IS NOT NULL THEN
    SELECT patient_id,status INTO v_patient,v_status FROM public.encounters WHERE id=_encounter_id;
    IF NOT FOUND OR v_patient<>_patient_id THEN RAISE EXCEPTION 'Encounter does not belong to the selected patient'; END IF;
    IF v_status IN ('completed','cancelled') THEN RAISE EXCEPTION 'Cannot schedule transfusion for a completed or cancelled encounter'; END IF;
  END IF;
  INSERT INTO public.transfusion_records(patient_id,blood_group,component,unit_identifier,consent_confirmed,status,encounter_id)
  VALUES (_patient_id,NULLIF(trim(COALESCE(_blood_group,'')),''),trim(_blood_product),NULLIF(trim(COALESCE(_unit_identifier,'')),''),true,'issued',_encounter_id)
  RETURNING id INTO v_id;
  RETURN v_id;
END; $$;

CREATE OR REPLACE FUNCTION public.record_transfusion_event(_record_id uuid, _status text, _reaction_observed boolean DEFAULT false, _reaction_notes text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE uid uuid:=auth.uid(); r public.transfusion_records%ROWTYPE; encounter_status text;
BEGIN
 IF uid IS NULL OR NOT (public.has_role(uid,'admin') OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse') OR public.has_role(uid,'midwife')) THEN RAISE EXCEPTION 'Clinical role required'; END IF;
 IF _status NOT IN ('issued','running','completed','stopped','cancelled') THEN RAISE EXCEPTION 'Invalid transfusion status'; END IF;
 SELECT * INTO r FROM public.transfusion_records WHERE id=_record_id FOR UPDATE; IF r.id IS NULL THEN RAISE EXCEPTION 'Transfusion record not found'; END IF;
 IF r.status IN ('completed','stopped','cancelled') AND _status<>r.status THEN RAISE EXCEPTION 'Closed transfusion record cannot be reopened'; END IF;
 IF r.encounter_id IS NOT NULL THEN
   SELECT status INTO encounter_status FROM public.encounters WHERE id=r.encounter_id;
   IF NOT FOUND THEN RAISE EXCEPTION 'Linked encounter not found'; END IF;
   IF encounter_status='cancelled' OR (encounter_status='completed' AND _status NOT IN ('completed','stopped','cancelled')) THEN RAISE EXCEPTION 'Cannot change transfusion lifecycle for a closed encounter'; END IF;
 END IF;
 UPDATE public.transfusion_records SET status=_status,reaction_observed=COALESCE(_reaction_observed,false),reaction_notes=CASE WHEN COALESCE(_reaction_observed,false) THEN _reaction_notes ELSE reaction_notes END,started_at=CASE WHEN _status='running' AND started_at IS NULL THEN now() ELSE started_at END,completed_at=CASE WHEN _status IN ('completed','stopped') THEN COALESCE(completed_at,now()) ELSE completed_at END,administered_by=COALESCE(administered_by,uid),updated_at=now() WHERE id=_record_id;
 RETURN jsonb_build_object('record_id',_record_id,'status',_status,'reaction_observed',COALESCE(_reaction_observed,false));
END; $$;

REVOKE INSERT, UPDATE, DELETE ON TABLE public.theatre_cases, public.emergency_cases, public.transfusion_records FROM authenticated;
REVOKE ALL ON FUNCTION public.create_theatre_case(uuid,text,timestamptz,text,text,uuid,uuid,uuid) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.transition_theatre_case(uuid,text,text) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.create_emergency_case(uuid,text,text,text,uuid) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.transition_emergency_case(uuid,text,text) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.create_transfusion_record(uuid,text,text,text,boolean,uuid) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.record_transfusion_event(uuid,text,boolean,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.create_theatre_case(uuid,text,timestamptz,text,text,uuid,uuid,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.transition_theatre_case(uuid,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_emergency_case(uuid,text,text,text,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.transition_emergency_case(uuid,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_transfusion_record(uuid,text,text,text,boolean,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_transfusion_event(uuid,text,boolean,text) TO authenticated;
