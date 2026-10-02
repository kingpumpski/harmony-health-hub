-- Gate A: harden encounter clerking writes against facility and test-mode boundary bypasses.
CREATE OR REPLACE FUNCTION public.save_encounter_clerking(
  _encounter_id uuid,
  _chief_complaint text DEFAULT NULL,
  _symptoms text DEFAULT NULL,
  _history_of_present_illness text DEFAULT NULL,
  _clerking_notes text DEFAULT NULL,
  _assessment text DEFAULT NULL,
  _plan text DEFAULT NULL,
  _treatment_plan text DEFAULT NULL,
  _follow_up_date date DEFAULT NULL
)
RETURNS public.encounters
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  uid uuid := auth.uid();
  v_facility uuid;
  v_encounter public.encounters;
  v_patient_facility uuid;
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF NOT (
    public.has_role(uid, 'admin')
    OR public.has_role(uid, 'it_admin')
    OR public.has_role(uid, 'practitioner')
    OR public.has_role(uid, 'nurse')
    OR public.has_role(uid, 'midwife')
    OR public.has_role(uid, 'specialist_nurse')
  ) THEN
    RAISE EXCEPTION 'Clinical access required';
  END IF;

  SELECT * INTO v_encounter
  FROM public.encounters
  WHERE id = _encounter_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Encounter not found';
  END IF;

  SELECT facility_id INTO v_patient_facility
  FROM public.patients
  WHERE id = v_encounter.patient_id
  FOR SHARE;

  IF v_encounter.facility_id IS NULL OR v_patient_facility IS NULL THEN
    RAISE EXCEPTION 'Encounter or patient facility attribution is unresolved';
  END IF;

  -- TEST MODE MUST PRECEDE privileged-role exceptions.
  IF public.hms_test_mode_enabled() THEN
    IF v_encounter.facility_id IS DISTINCT FROM public.hms_test_facility_id()
       OR v_patient_facility IS DISTINCT FROM public.hms_test_facility_id() THEN
      RAISE EXCEPTION 'Test mode permits clerking only within TEST-0001';
    END IF;
  ELSE
    v_facility := public.current_user_facility_id();

    IF public.has_role(uid, 'admin') OR public.has_role(uid, 'it_admin') THEN
      NULL;
    ELSIF v_facility IS NULL
       OR v_encounter.facility_id IS DISTINCT FROM v_facility
       OR v_patient_facility IS DISTINCT FROM v_facility THEN
      RAISE EXCEPTION 'Encounter belongs to a different facility context';
    END IF;
  END IF;

  IF v_encounter.practitioner_id IS DISTINCT FROM uid
     AND NOT (public.has_role(uid, 'admin') OR public.has_role(uid, 'it_admin')) THEN
    RAISE EXCEPTION 'Only the encounter creator or an administrator may save this clerking sheet';
  END IF;

  IF v_encounter.status <> 'draft' THEN
    RAISE EXCEPTION 'Only draft encounters can be edited';
  END IF;

  UPDATE public.encounters
  SET chief_complaint = NULLIF(pg_catalog.btrim(_chief_complaint), ''),
      symptoms = NULLIF(pg_catalog.btrim(_symptoms), ''),
      history_of_present_illness = NULLIF(pg_catalog.btrim(_history_of_present_illness), ''),
      clerking_notes = NULLIF(pg_catalog.btrim(_clerking_notes), ''),
      assessment = NULLIF(pg_catalog.btrim(_assessment), ''),
      plan = NULLIF(pg_catalog.btrim(_plan), ''),
      treatment_plan = NULLIF(pg_catalog.btrim(_treatment_plan), ''),
      follow_up_date = _follow_up_date,
      updated_at = pg_catalog.now()
  WHERE id = _encounter_id
  RETURNING * INTO v_encounter;

  RETURN v_encounter;
END;
$function$;

REVOKE ALL ON FUNCTION public.save_encounter_clerking(uuid,text,text,text,text,text,text,text,date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.save_encounter_clerking(uuid,text,text,text,text,text,text,text,date) TO authenticated;
NOTIFY pgrst, 'reload schema';
