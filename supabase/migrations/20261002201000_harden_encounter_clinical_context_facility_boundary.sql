-- Gate A: clinical context must honor the same patient/encounter facility boundary as the encounter workspace.
CREATE OR REPLACE FUNCTION public.get_encounter_clinical_context(_patient_id uuid, _encounter_id uuid DEFAULT NULL::uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE
  v_user uuid := auth.uid();
  v_facility uuid := public.current_user_facility_id();
  v_test_facility uuid := public.hms_test_facility_id();
  v_patient_facility uuid;
  v_encounter_facility uuid;
  v_patient jsonb;
  v_history jsonb;
  v_vitals jsonb;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (
    public.has_role(v_user,'admin') OR public.has_role(v_user,'practitioner') OR
    public.has_role(v_user,'nurse') OR public.has_role(v_user,'midwife') OR
    public.has_role(v_user,'specialist_nurse')
  ) THEN RAISE EXCEPTION 'Clinical access required'; END IF;

  SELECT p.facility_id INTO v_patient_facility
  FROM public.patients p WHERE p.id = _patient_id AND p.status = 'active';
  IF v_patient_facility IS NULL THEN RAISE EXCEPTION 'Patient facility attribution is unresolved'; END IF;

  IF public.hms_test_mode_enabled() THEN
    IF v_patient_facility <> v_test_facility THEN
      RAISE EXCEPTION 'Test mode facility boundary violation';
    END IF;
  ELSIF NOT public.has_role(v_user,'admin') THEN
    IF v_facility IS NULL OR v_patient_facility <> v_facility THEN
      RAISE EXCEPTION 'Patient is outside the active facility';
    END IF;
  END IF;

  IF _encounter_id IS NOT NULL THEN
    SELECT e.facility_id INTO v_encounter_facility
    FROM public.encounters e
    WHERE e.id = _encounter_id AND e.patient_id = _patient_id;
    IF v_encounter_facility IS NULL THEN RAISE EXCEPTION 'Encounter does not belong to patient'; END IF;
    IF public.hms_test_mode_enabled() THEN
      IF v_encounter_facility <> v_test_facility THEN RAISE EXCEPTION 'Test mode encounter facility boundary violation'; END IF;
    ELSIF NOT public.has_role(v_user,'admin') THEN
      IF v_facility IS NULL OR v_encounter_facility <> v_facility THEN RAISE EXCEPTION 'Encounter is outside the active facility'; END IF;
    END IF;
  END IF;

  SELECT jsonb_build_object('patient_code',p.patient_code,'name',concat_ws(' ',p.first_name,p.last_name),
    'blood_group',p.blood_group,'genotype',p.genotype,'allergies',NULLIF(trim(p.allergies),''),
    'chronic_conditions',NULLIF(trim(p.chronic_conditions),'')) INTO v_patient
  FROM public.patients p WHERE p.id=_patient_id AND p.status='active';

  SELECT COALESCE(jsonb_agg(x ORDER BY x.created_at DESC),'[]'::jsonb) INTO v_history
  FROM (
    SELECT jsonb_build_object('id',e.id,'created_at',e.created_at,'status',e.status,
      'principal_diagnosis',e.principal_diagnosis,'symptoms',e.symptoms,'treatment_plan',e.treatment_plan,
      'diagnoses',COALESCE((SELECT jsonb_agg(d.diagnosis ORDER BY d.is_principal DESC,d.created_at DESC)
        FROM public.diagnoses d WHERE d.encounter_id=e.id),'[]'::jsonb)) x,e.created_at
    FROM public.encounters e
    WHERE e.patient_id=_patient_id AND (_encounter_id IS NULL OR e.id<>_encounter_id)
      AND ((public.hms_test_mode_enabled() AND e.facility_id=v_test_facility)
        OR (NOT public.hms_test_mode_enabled() AND (public.has_role(v_user,'admin') OR e.facility_id=v_facility)))
    ORDER BY e.created_at DESC LIMIT 8
  ) x;

  SELECT COALESCE(jsonb_agg(jsonb_build_object('recorded_at',v.recorded_at,'systolic',v.systolic,
    'diastolic',v.diastolic,'pulse_rate',v.pulse_rate,'temperature',v.temperature,
    'respiratory_rate',v.respiratory_rate,'oxygen_saturation',v.oxygen_saturation,'weight_kg',v.weight_kg,
    'bmi',v.bmi,'priority',v.priority,'notes',v.notes) ORDER BY v.recorded_at DESC),'[]'::jsonb) INTO v_vitals
  FROM (SELECT * FROM public.vital_signs WHERE patient_id=_patient_id ORDER BY recorded_at DESC LIMIT 3) v;

  RETURN jsonb_build_object('patient',v_patient,'previous_encounters',v_history,'recent_vitals',v_vitals);
END;
$function$;

REVOKE ALL ON FUNCTION public.get_encounter_clinical_context(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_encounter_clinical_context(uuid, uuid) TO authenticated;
NOTIFY pgrst, 'reload schema';
