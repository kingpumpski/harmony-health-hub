-- Harden high-risk patient clinical writes with explicit facility lineage.
CREATE OR REPLACE FUNCTION public.create_fertility_cycle_workflow(
  _patient_id uuid,
  _partner_name text DEFAULT NULL::text,
  _cycle_type text DEFAULT 'IVF'::text,
  _start_date date DEFAULT CURRENT_DATE,
  _protocol text DEFAULT NULL::text
)
RETURNS public.fertility_cycles
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  uid uuid := auth.uid();
  v_cycle public.fertility_cycles;
  v_cycle_number integer;
  v_facility uuid;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (
    public.has_role(uid,'admin') OR public.has_role(uid,'it_admin')
    OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse')
    OR public.has_role(uid,'midwife')
  ) THEN RAISE EXCEPTION 'Insufficient role for fertility workflow'; END IF;
  v_facility := public.assert_patient_facility_context(_patient_id);
  IF upper(pg_catalog.btrim(_cycle_type)) NOT IN ('IVF','IUI','ICSI','FET')
    THEN RAISE EXCEPTION 'Unsupported fertility cycle type'; END IF;
  SELECT COALESCE(MAX(cycle_number),0)+1 INTO v_cycle_number
  FROM public.fertility_cycles WHERE patient_id=_patient_id;
  INSERT INTO public.fertility_cycles(
    patient_id, facility_id, partner_name, cycle_type, cycle_number,
    start_date, protocol, status, assigned_specialist
  )
  VALUES(
    _patient_id, v_facility, NULLIF(pg_catalog.btrim(_partner_name),''),
    upper(pg_catalog.btrim(_cycle_type)), v_cycle_number, _start_date,
    NULLIF(pg_catalog.btrim(_protocol),''), 'active', uid
  )
  RETURNING * INTO v_cycle;
  PERFORM public.record_system_audit(
    'fertility_cycle_created','fertility','fertility_cycle',v_cycle.id,'info',
    pg_catalog.jsonb_build_object('patient_id',_patient_id,'cycle_type',v_cycle.cycle_type,'facility_id',v_facility)
  );
  RETURN v_cycle;
END;
$function$;

CREATE OR REPLACE FUNCTION public.create_meal_plan_workflow(
  _patient_id uuid, _plan_type text, _restrictions text DEFAULT NULL::text
)
RETURNS public.meal_plans
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  uid uuid := auth.uid();
  v_plan public.meal_plans;
  v_type text := NULLIF(pg_catalog.btrim(COALESCE(_plan_type,'')),'');
  v_facility uuid;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (
    public.has_role(uid,'admin') OR public.has_role(uid,'it_admin')
    OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse')
    OR public.has_role(uid,'midwife') OR public.has_role(uid,'specialist_nurse')
    OR public.has_role(uid,'canteen')
  ) THEN RAISE EXCEPTION 'Meal plan creation is not permitted'; END IF;
  v_facility := public.assert_patient_facility_context(_patient_id);
  IF v_type IS NULL THEN RAISE EXCEPTION 'Meal plan type is required'; END IF;
  INSERT INTO public.meal_plans(
    patient_id, facility_id, plan_type, restrictions, created_by, active
  )
  VALUES(
    _patient_id, v_facility, v_type,
    NULLIF(pg_catalog.btrim(COALESCE(_restrictions,'')),''),
    uid, TRUE
  )
  RETURNING * INTO v_plan;
  PERFORM public.record_system_audit(
    'meal_plan_created','canteen','meal_plan',v_plan.id,'info',
    pg_catalog.jsonb_build_object('patient_id',_patient_id,'plan_type',v_type,'facility_id',v_facility,'actor_user_id',uid)
  );
  RETURN v_plan;
END;
$function$;

CREATE OR REPLACE FUNCTION public.create_nursing_care_plan(
  _patient_id uuid, _problem text, _goal text, _interventions text,
  _priority text DEFAULT 'routine'::text,
  _encounter_id uuid DEFAULT NULL::uuid,
  _admission_id uuid DEFAULT NULL::uuid
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  uid uuid := auth.uid();
  v_id uuid;
  v_facility uuid;
BEGIN
  IF uid IS NULL OR NOT (
    public.has_role(uid,'admin') OR public.has_role(uid,'it_admin')
    OR public.has_role(uid,'nurse') OR public.has_role(uid,'midwife')
  ) THEN
    RAISE EXCEPTION 'Not authorized to create nursing care plans';
  END IF;
  IF _patient_id IS NULL
     OR NULLIF(pg_catalog.btrim(_problem),'') IS NULL
     OR NULLIF(pg_catalog.btrim(_goal),'') IS NULL
  THEN RAISE EXCEPTION 'Patient, problem and goal are required'; END IF;
  v_facility := public.assert_patient_facility_context(_patient_id);
  INSERT INTO public.nursing_care_plans(
    patient_id, facility_id, encounter_id, admission_id, problem, goal,
    interventions, priority, created_by
  )
  VALUES(
    _patient_id, v_facility, _encounter_id, _admission_id,
    pg_catalog.btrim(_problem), pg_catalog.btrim(_goal),
    NULLIF(pg_catalog.btrim(COALESCE(_interventions,'')),''),
    COALESCE(NULLIF(pg_catalog.btrim(_priority),''),'routine'), uid
  )
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.record_triage_assessment(
  _patient_id uuid, _systolic integer DEFAULT NULL, _diastolic integer DEFAULT NULL,
  _heart_rate integer DEFAULT NULL, _temperature numeric DEFAULT NULL,
  _respiratory_rate integer DEFAULT NULL, _oxygen_saturation numeric DEFAULT NULL,
  _weight_kg numeric DEFAULT NULL, _height_m numeric DEFAULT NULL,
  _pain_score integer DEFAULT NULL, _consciousness text DEFAULT NULL,
  _presenting_complaint text DEFAULT NULL, _clinical_notes text DEFAULT NULL,
  _priority text DEFAULT 'routine'
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  uid uuid := auth.uid();
  v_id uuid;
  v_bmi numeric(7,2);
  v_priority text := lower(pg_catalog.btrim(coalesce(_priority, 'routine')));
  v_facility uuid;
BEGIN
  IF uid IS NULL OR NOT (
    public.has_role(uid,'admin') OR public.has_role(uid,'it_admin')
    OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse')
    OR public.has_role(uid,'midwife') OR public.has_role(uid,'specialist_nurse')
  ) THEN RAISE EXCEPTION 'Not authorized to record triage'; END IF;
  v_facility := public.assert_patient_facility_context(_patient_id);
  IF v_priority NOT IN ('critical','urgent','moderate','routine')
    THEN RAISE EXCEPTION 'Invalid triage priority'; END IF;
  IF _pain_score IS NOT NULL AND (_pain_score < 0 OR _pain_score > 10)
    THEN RAISE EXCEPTION 'Pain score must be between 0 and 10'; END IF;
  IF _systolic IS NOT NULL AND (_systolic < 0 OR _systolic > 400)
    THEN RAISE EXCEPTION 'SBP must be between 0 and 400 mmHg'; END IF;
  IF _diastolic IS NOT NULL AND (_diastolic < 0 OR _diastolic > 300)
    THEN RAISE EXCEPTION 'DBP must be between 0 and 300 mmHg'; END IF;
  IF _heart_rate IS NOT NULL AND (_heart_rate < 0 OR _heart_rate > 300)
    THEN RAISE EXCEPTION 'Heart rate must be between 0 and 300 bpm'; END IF;
  IF _temperature IS NOT NULL AND (_temperature < 20 OR _temperature > 50)
    THEN RAISE EXCEPTION 'Temperature must be between 20 and 50 °C'; END IF;
  IF _respiratory_rate IS NOT NULL AND (_respiratory_rate < 0 OR _respiratory_rate > 100)
    THEN RAISE EXCEPTION 'Respiratory rate must be between 0 and 100 per minute'; END IF;
  IF _oxygen_saturation IS NOT NULL AND (_oxygen_saturation < 0 OR _oxygen_saturation > 100)
    THEN RAISE EXCEPTION 'Oxygen saturation must be between 0 and 100 percent'; END IF;
  IF _weight_kg IS NOT NULL AND (_weight_kg <= 0 OR _weight_kg > 500)
    THEN RAISE EXCEPTION 'Weight must be greater than 0 and no more than 500 kg'; END IF;
  IF _height_m IS NOT NULL AND (_height_m <= 0 OR _height_m > 3)
    THEN RAISE EXCEPTION 'Height must be entered in metres and be between 0 and 3 m'; END IF;
  IF _weight_kg IS NOT NULL AND _height_m IS NOT NULL AND _weight_kg > 0 AND _height_m > 0 THEN
    v_bmi := pg_catalog.round((_weight_kg / pg_catalog.power(_height_m, 2))::numeric, 2);
  END IF;
  INSERT INTO public.triage_assessments(
    patient_id, facility_id, recorded_by, systolic, diastolic, heart_rate,
    temperature, respiratory_rate, oxygen_saturation, weight_kg, height_m, bmi,
    pain_score, consciousness, presenting_complaint, clinical_notes, priority, is_critical
  )
  VALUES(
    _patient_id, v_facility, uid, _systolic, _diastolic, _heart_rate,
    _temperature, _respiratory_rate, _oxygen_saturation, _weight_kg, _height_m,
    v_bmi, _pain_score, NULLIF(pg_catalog.btrim(_consciousness), ''),
    NULLIF(pg_catalog.btrim(_presenting_complaint), ''),
    NULLIF(pg_catalog.btrim(_clinical_notes), ''), v_priority, v_priority = 'critical'
  )
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.schedule_medication_administration(
  _patient_id uuid, _medication_name text, _dose text DEFAULT NULL,
  _route text DEFAULT NULL, _scheduled_at timestamptz DEFAULT NULL,
  _notes text DEFAULT NULL, _due_window_minutes integer DEFAULT 30
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  uid uuid := auth.uid();
  v_id uuid;
  v_facility uuid;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (
    public.has_role(uid,'admin') OR public.has_role(uid,'it_admin')
    OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse')
    OR public.has_role(uid,'midwife') OR public.has_role(uid,'pharmacist')
  ) THEN RAISE EXCEPTION 'Clinical medication role required'; END IF;
  v_facility := public.assert_patient_facility_context(_patient_id);
  IF NULLIF(pg_catalog.btrim(_medication_name),'') IS NULL
    THEN RAISE EXCEPTION 'Medication name is required'; END IF;
  IF COALESCE(_due_window_minutes,30)<1 OR COALESCE(_due_window_minutes,30)>1440
    THEN RAISE EXCEPTION 'Invalid due window'; END IF;
  INSERT INTO public.medication_administrations(
    patient_id, facility_id, medication_name, dose, route, scheduled_at,
    notes, due_window_minutes, status
  )
  VALUES(
    _patient_id, v_facility, pg_catalog.btrim(_medication_name),
    NULLIF(pg_catalog.btrim(_dose),''), NULLIF(pg_catalog.btrim(_route),''),
    _scheduled_at, NULLIF(pg_catalog.btrim(_notes),''), COALESCE(_due_window_minutes,30),
    'scheduled'
  )
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.create_fertility_cycle_workflow(uuid,text,text,date,text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.create_meal_plan_workflow(uuid,text,text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.create_nursing_care_plan(uuid,text,text,text,text,uuid,uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.record_triage_assessment(uuid,integer,integer,integer,numeric,integer,numeric,numeric,numeric,integer,text,text,text,text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.schedule_medication_administration(uuid,text,text,text,timestamptz,text,integer) FROM anon;
GRANT EXECUTE ON FUNCTION public.create_fertility_cycle_workflow(uuid,text,text,date,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_meal_plan_workflow(uuid,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_nursing_care_plan(uuid,text,text,text,text,uuid,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_triage_assessment(uuid,integer,integer,integer,numeric,integer,numeric,numeric,numeric,integer,text,text,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.schedule_medication_administration(uuid,text,text,text,timestamptz,text,integer) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.create_fertility_cycle_workflow(uuid,text,text,date,text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.create_meal_plan_workflow(uuid,text,text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.create_nursing_care_plan(uuid,text,text,text,text,uuid,uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.record_triage_assessment(uuid,integer,integer,integer,numeric,integer,numeric,numeric,numeric,integer,text,text,text,text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.schedule_medication_administration(uuid,text,text,text,timestamptz,text,integer) FROM PUBLIC;
NOTIFY pgrst,'reload schema';