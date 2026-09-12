-- Secure write paths for high-risk operational workflows.
-- Direct table writes remain restricted by RLS; lifecycle mutations use these functions.

CREATE OR REPLACE FUNCTION public.create_nursing_care_plan(
  _patient_id UUID,
  _problem TEXT,
  _goal TEXT,
  _interventions TEXT,
  _priority TEXT DEFAULT 'routine',
  _encounter_id UUID DEFAULT NULL,
  _admission_id UUID DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_id UUID;
BEGIN
  IF auth.uid() IS NULL OR NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife') OR public.has_role(auth.uid(),'specialist_nurse')) THEN
    RAISE EXCEPTION 'Not authorized to create nursing care plans';
  END IF;
  INSERT INTO public.nursing_care_plans(patient_id, encounter_id, admission_id, problem, goal, interventions, priority, created_by)
  VALUES (_patient_id,_encounter_id,_admission_id,_problem,_goal,_interventions,COALESCE(_priority,'routine'),auth.uid()) RETURNING id INTO v_id;
  RETURN v_id;
END; $$;

CREATE OR REPLACE FUNCTION public.create_theatre_case(
  _patient_id UUID,
  _procedure_name TEXT,
  _scheduled_start TIMESTAMPTZ DEFAULT NULL,
  _theatre_name TEXT DEFAULT NULL,
  _urgency TEXT DEFAULT 'elective',
  _surgeon_id UUID DEFAULT NULL,
  _anesthetist_id UUID DEFAULT NULL,
  _encounter_id UUID DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_id UUID;
BEGIN
  IF auth.uid() IS NULL OR NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'specialist_nurse')) THEN
    RAISE EXCEPTION 'Not authorized to create theatre cases';
  END IF;
  INSERT INTO public.theatre_cases(patient_id,encounter_id,procedure_name,surgeon_id,anesthetist_id,scheduled_start,theatre_name,urgency,status,created_by)
  VALUES (_patient_id,_encounter_id,_procedure_name,_surgeon_id,_anesthetist_id,_scheduled_start,_theatre_name,COALESCE(_urgency,'elective'),'requested',auth.uid()) RETURNING id INTO v_id;
  RETURN v_id;
END; $$;

CREATE OR REPLACE FUNCTION public.create_transfusion_record(
  _patient_id UUID,
  _blood_product TEXT,
  _unit_identifier TEXT,
  _blood_group TEXT DEFAULT NULL,
  _consent_confirmed BOOLEAN DEFAULT FALSE,
  _encounter_id UUID DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_id UUID;
BEGIN
  IF auth.uid() IS NULL OR NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'specialist_nurse')) THEN
    RAISE EXCEPTION 'Not authorized to create transfusion records';
  END IF;
  INSERT INTO public.transfusion_records(patient_id,encounter_id,blood_product,unit_identifier,blood_group,consent_confirmed,status)
  VALUES (_patient_id,_encounter_id,_blood_product,_unit_identifier,_blood_group,COALESCE(_consent_confirmed,FALSE),'planned') RETURNING id INTO v_id;
  RETURN v_id;
END; $$;

CREATE OR REPLACE FUNCTION public.transition_medication_administration(
  _record_id UUID,
  _status TEXT,
  _reason TEXT DEFAULT NULL,
  _notes TEXT DEFAULT NULL,
  _witnessed_by UUID DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v public.medication_administrations;
BEGIN
  IF auth.uid() IS NULL OR NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife') OR public.has_role(auth.uid(),'specialist_nurse') OR public.has_role(auth.uid(),'pharmacist')) THEN
    RAISE EXCEPTION 'Not authorized to administer medication';
  END IF;
  IF _status NOT IN ('administered','held','refused','omitted','cancelled') THEN RAISE EXCEPTION 'Invalid medication status'; END IF;
  SELECT * INTO v FROM public.medication_administrations WHERE id=_record_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Medication administration record not found'; END IF;
  IF v.status IN ('cancelled','administered','refused','omitted') THEN RAISE EXCEPTION 'Medication record is already closed'; END IF;
  UPDATE public.medication_administrations
  SET status=_status,
      reason=COALESCE(_reason,reason),
      notes=COALESCE(_notes,notes),
      administered_at=CASE WHEN _status='administered' THEN now() ELSE administered_at END,
      administered_by=CASE WHEN _status IN ('administered','held','refused','omitted') THEN auth.uid() ELSE administered_by END,
      witnessed_by=COALESCE(_witnessed_by,witnessed_by)
  WHERE id=_record_id;
  RETURN _record_id;
END; $$;

REVOKE ALL ON FUNCTION public.create_nursing_care_plan(UUID,TEXT,TEXT,TEXT,TEXT,UUID,UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_nursing_care_plan(UUID,TEXT,TEXT,TEXT,TEXT,UUID,UUID) TO authenticated;
REVOKE ALL ON FUNCTION public.create_theatre_case(UUID,TEXT,TIMESTAMPTZ,TEXT,TEXT,UUID,UUID,UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_theatre_case(UUID,TEXT,TIMESTAMPTZ,TEXT,TEXT,UUID,UUID,UUID) TO authenticated;
REVOKE ALL ON FUNCTION public.create_transfusion_record(UUID,TEXT,TEXT,TEXT,BOOLEAN,UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_transfusion_record(UUID,TEXT,TEXT,TEXT,BOOLEAN,UUID) TO authenticated;
REVOKE ALL ON FUNCTION public.transition_medication_administration(UUID,TEXT,TEXT,TEXT,UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.transition_medication_administration(UUID,TEXT,TEXT,TEXT,UUID) TO authenticated;
