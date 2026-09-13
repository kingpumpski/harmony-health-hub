-- Secure nursing care-plan creation and review lifecycle.

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
DECLARE uid UUID := auth.uid(); v_id UUID;
BEGIN
  IF uid IS NULL OR NOT (public.has_role(uid,'admin') OR public.has_role(uid,'nurse') OR public.has_role(uid,'midwife') OR public.has_role(uid,'specialist_nurse') OR public.has_role(uid,'practitioner')) THEN RAISE EXCEPTION 'Clinical role required'; END IF;
  IF _patient_id IS NULL OR NULLIF(trim(_problem),'') IS NULL OR NULLIF(trim(_goal),'') IS NULL OR NULLIF(trim(_interventions),'') IS NULL THEN RAISE EXCEPTION 'Patient, problem, goal and interventions are required'; END IF;
  IF _priority NOT IN ('routine','high','critical') THEN RAISE EXCEPTION 'Invalid care-plan priority'; END IF;
  INSERT INTO public.nursing_care_plans(patient_id,encounter_id,admission_id,problem,goal,interventions,priority,status,created_by) VALUES (_patient_id,_encounter_id,_admission_id,trim(_problem),trim(_goal),trim(_interventions),_priority,'active',uid) RETURNING id INTO v_id;
  RETURN v_id;
END; $$;

CREATE OR REPLACE FUNCTION public.review_nursing_care_plan(
  _plan_id UUID,
  _status TEXT,
  _evaluation TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE uid UUID := auth.uid();
BEGIN
  IF uid IS NULL OR NOT (public.has_role(uid,'admin') OR public.has_role(uid,'nurse') OR public.has_role(uid,'midwife') OR public.has_role(uid,'specialist_nurse') OR public.has_role(uid,'practitioner')) THEN RAISE EXCEPTION 'Clinical role required'; END IF;
  IF _status NOT IN ('active','on_hold','completed','cancelled') THEN RAISE EXCEPTION 'Invalid care-plan status'; END IF;
  UPDATE public.nursing_care_plans SET status=_status,evaluation=COALESCE(_evaluation,evaluation),reviewed_by=uid,reviewed_at=now() WHERE id=_plan_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Care plan not found'; END IF;
  RETURN jsonb_build_object('plan_id',_plan_id,'status',_status);
END; $$;

REVOKE ALL ON FUNCTION public.create_nursing_care_plan(UUID,TEXT,TEXT,TEXT,TEXT,UUID,UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_nursing_care_plan(UUID,TEXT,TEXT,TEXT,TEXT,UUID,UUID) TO authenticated;
REVOKE ALL ON FUNCTION public.review_nursing_care_plan(UUID,TEXT,TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.review_nursing_care_plan(UUID,TEXT,TEXT) TO authenticated;
