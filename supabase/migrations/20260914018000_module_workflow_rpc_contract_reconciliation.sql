-- Reconcile application workflow RPCs with the canonical production schema.
-- Preserve existing canonical columns; functions map UI terminology to them.

CREATE OR REPLACE FUNCTION public.create_nursing_care_plan(_patient_id uuid,_problem text,_goal text,_interventions text,_priority text DEFAULT 'routine',_encounter_id uuid DEFAULT NULL,_admission_id uuid DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_id uuid;
BEGIN
 IF auth.uid() IS NULL OR NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife')) THEN RAISE EXCEPTION 'Not authorized to create nursing care plans'; END IF;
 IF _patient_id IS NULL OR NULLIF(trim(_problem),'') IS NULL OR NULLIF(trim(_goal),'') IS NULL THEN RAISE EXCEPTION 'Patient, problem and goal are required'; END IF;
 INSERT INTO public.nursing_care_plans(patient_id,encounter_id,admission_id,problem,goal,interventions,priority,created_by) VALUES (_patient_id,_encounter_id,_admission_id,trim(_problem),trim(_goal),NULLIF(trim(COALESCE(_interventions,'')),''),COALESCE(NULLIF(trim(_priority),''),'routine'),auth.uid()) RETURNING id INTO v_id;
 RETURN v_id;
END; $$;

CREATE OR REPLACE FUNCTION public.create_theatre_case(_patient_id uuid,_procedure_name text,_scheduled_start timestamptz DEFAULT NULL,_theatre_name text DEFAULT NULL,_urgency text DEFAULT 'elective',_surgeon_id uuid DEFAULT NULL,_anesthetist_id uuid DEFAULT NULL,_encounter_id uuid DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_id uuid;
BEGIN
 IF auth.uid() IS NULL OR NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife')) THEN RAISE EXCEPTION 'Not authorized to create theatre cases'; END IF;
 IF _patient_id IS NULL OR NULLIF(trim(_procedure_name),'') IS NULL THEN RAISE EXCEPTION 'Patient and procedure are required'; END IF;
 INSERT INTO public.theatre_cases(patient_id,procedure_name,surgeon_id,anaesthetist_id,scheduled_at,theatre,status,created_by) VALUES (_patient_id,trim(_procedure_name),_surgeon_id,_anesthetist_id,_scheduled_start,NULLIF(trim(COALESCE(_theatre_name,'')),''),COALESCE(NULLIF(trim(_urgency),''),'elective'),auth.uid()) RETURNING id INTO v_id;
 RETURN v_id;
END; $$;

CREATE OR REPLACE FUNCTION public.create_transfusion_record(_patient_id uuid,_blood_product text,_unit_identifier text,_blood_group text DEFAULT NULL,_consent_confirmed boolean DEFAULT false,_encounter_id uuid DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_id uuid;
BEGIN
 IF auth.uid() IS NULL OR NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife')) THEN RAISE EXCEPTION 'Not authorized to create transfusion records'; END IF;
 IF _patient_id IS NULL OR NULLIF(trim(_blood_product),'') IS NULL THEN RAISE EXCEPTION 'Patient and blood product are required'; END IF;
 INSERT INTO public.transfusion_records(patient_id,blood_group,component,unit_identifier,consent_confirmed,status) VALUES (_patient_id,NULLIF(trim(COALESCE(_blood_group,'')),''),trim(_blood_product),NULLIF(trim(COALESCE(_unit_identifier,'')),''),COALESCE(_consent_confirmed,false),'issued') RETURNING id INTO v_id;
 RETURN v_id;
END; $$;

CREATE OR REPLACE FUNCTION public.transition_emergency_case(_case_id uuid,_status text,_disposition text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE uid uuid := auth.uid(); c public.emergency_cases%ROWTYPE;
BEGIN
 IF uid IS NULL OR NOT (public.has_role(uid,'admin') OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse') OR public.has_role(uid,'midwife')) THEN RAISE EXCEPTION 'Clinical role required'; END IF;
 IF _status NOT IN ('waiting','triage','treatment','observation','admitted','discharged','referred','left_without_being_seen','cancelled') THEN RAISE EXCEPTION 'Invalid emergency status'; END IF;
 SELECT * INTO c FROM public.emergency_cases WHERE id=_case_id FOR UPDATE; IF c.id IS NULL THEN RAISE EXCEPTION 'Emergency case not found'; END IF;
 UPDATE public.emergency_cases SET status=_status,disposition=COALESCE(NULLIF(trim(_disposition),''),disposition),assigned_officer=COALESCE(assigned_officer,uid),updated_at=now() WHERE id=_case_id;
 RETURN jsonb_build_object('case_id',_case_id,'status',_status);
END; $$;

CREATE OR REPLACE FUNCTION public.transition_theatre_case(_case_id uuid,_status text,_cancellation_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE uid uuid := auth.uid(); c public.theatre_cases%ROWTYPE;
BEGIN
 IF uid IS NULL OR NOT (public.has_role(uid,'admin') OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse') OR public.has_role(uid,'midwife')) THEN RAISE EXCEPTION 'Clinical role required'; END IF;
 IF _status NOT IN ('requested','approved','scheduled','in_progress','completed','cancelled','postponed') THEN RAISE EXCEPTION 'Invalid theatre status'; END IF;
 SELECT * INTO c FROM public.theatre_cases WHERE id=_case_id FOR UPDATE; IF c.id IS NULL THEN RAISE EXCEPTION 'Theatre case not found'; END IF;
 UPDATE public.theatre_cases SET status=_status,notes=CASE WHEN _status IN ('cancelled','postponed') THEN COALESCE(NULLIF(trim(_cancellation_reason),''),notes) ELSE notes END,updated_at=now() WHERE id=_case_id;
 RETURN jsonb_build_object('case_id',_case_id,'status',_status);
END; $$;

REVOKE ALL ON FUNCTION public.create_nursing_care_plan(uuid,text,text,text,text,uuid,uuid) FROM PUBLIC; GRANT EXECUTE ON FUNCTION public.create_nursing_care_plan(uuid,text,text,text,text,uuid,uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.create_theatre_case(uuid,text,timestamptz,text,text,uuid,uuid,uuid) FROM PUBLIC; GRANT EXECUTE ON FUNCTION public.create_theatre_case(uuid,text,timestamptz,text,text,uuid,uuid,uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.create_transfusion_record(uuid,text,text,text,boolean,uuid) FROM PUBLIC; GRANT EXECUTE ON FUNCTION public.create_transfusion_record(uuid,text,text,text,boolean,uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.transition_emergency_case(uuid,text,text) FROM PUBLIC; GRANT EXECUTE ON FUNCTION public.transition_emergency_case(uuid,text,text) TO authenticated;
REVOKE ALL ON FUNCTION public.transition_theatre_case(uuid,text,text) FROM PUBLIC; GRANT EXECUTE ON FUNCTION public.transition_theatre_case(uuid,text,text) TO authenticated;
NOTIFY pgrst,'reload schema';
