-- Clinical read context linkage hardening.
-- Keeps attending history and active encounter context behind explicit clinical authorization
-- and verifies patient/encounter linkage before returning PHI.

CREATE OR REPLACE FUNCTION public.get_attending_patient_history(
  _patient_id UUID,
  _current_encounter_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r JSONB;
  uid UUID := auth.uid();
BEGIN
  IF uid IS NULL OR NOT (
    public.has_role(uid,'admin') OR public.has_role(uid,'practitioner') OR
    public.has_role(uid,'nurse') OR public.has_role(uid,'midwife') OR
    public.has_role(uid,'specialist_nurse')
  ) THEN
    RAISE EXCEPTION 'Not authorized to view attending clinical history';
  END IF;

  IF _patient_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.patients WHERE id = _patient_id
  ) THEN
    RAISE EXCEPTION 'Patient not found';
  END IF;

  IF _current_encounter_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.encounters
    WHERE id = _current_encounter_id AND patient_id = _patient_id
  ) THEN
    RAISE EXCEPTION 'Encounter does not belong to patient';
  END IF;

  SELECT jsonb_build_object(
    'patient', (
      SELECT jsonb_build_object(
        'id',p.id,'patient_code',p.patient_code,
        'name',concat_ws(' ',p.first_name,p.last_name),
        'blood_group',p.blood_group,'genotype',p.genotype,
        'allergies',NULLIF(trim(p.allergies),''),
        'chronic_conditions',NULLIF(trim(p.chronic_conditions),'')
      )
      FROM public.patients p WHERE p.id=_patient_id
    ),
    'prior_encounters', COALESCE((
      SELECT jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC)
      FROM (
        SELECT e.id,e.created_at,e.status,
          NULLIF(trim(e.principal_diagnosis),'') AS principal_diagnosis,
          NULLIF(left(trim(e.symptoms),280),'') AS presenting_symptoms,
          NULLIF(left(trim(e.treatment_plan),360),'') AS prior_treatment_plan
        FROM public.encounters e
        WHERE e.patient_id=_patient_id
          AND (_current_encounter_id IS NULL OR e.id<>_current_encounter_id)
        ORDER BY e.created_at DESC LIMIT 8
      ) x
    ),'[]'::jsonb),
    'major_diagnoses', COALESCE((
      SELECT jsonb_agg(to_jsonb(x) ORDER BY x.last_seen DESC)
      FROM (
        SELECT NULLIF(trim(d.diagnosis),'') AS diagnosis,
          max(e.created_at) AS last_seen,count(*)::int AS occurrences
        FROM public.diagnoses d
        JOIN public.encounters e ON e.id=d.encounter_id
        WHERE e.patient_id=_patient_id
          AND (_current_encounter_id IS NULL OR e.id<>_current_encounter_id)
          AND NULLIF(trim(d.diagnosis),'') IS NOT NULL
        GROUP BY NULLIF(trim(d.diagnosis),'')
        ORDER BY last_seen DESC LIMIT 12
      ) x
    ),'[]'::jsonb),
    'abnormal_labs', COALESCE((
      SELECT jsonb_agg(to_jsonb(x) ORDER BY x.entered_at DESC)
      FROM (
        SELECT lo.id AS lab_order_id,lo.test_name,lo.test_category,
          lr.interpretation,lr.result_data,lr.entered_at
        FROM public.lab_orders lo
        JOIN public.lab_results lr ON lr.lab_order_id=lo.id
        WHERE lo.patient_id=_patient_id AND lr.is_abnormal=true
        ORDER BY lr.entered_at DESC LIMIT 8
      ) x
    ),'[]'::jsonb),
    'recent_prescriptions', COALESCE((
      SELECT jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC)
      FROM (
        SELECT pr.medication,pr.dosage,pr.frequency,pr.duration,pr.status,pr.created_at
        FROM public.prescriptions pr
        WHERE pr.patient_id=_patient_id AND pr.status<>'cancelled'
        ORDER BY pr.created_at DESC LIMIT 8
      ) x
    ),'[]'::jsonb),
    'latest_triage', (
      SELECT to_jsonb(x) FROM (
        SELECT v.recorded_at,v.priority,v.systolic,v.diastolic,v.pulse_rate,
          v.temperature,v.respiratory_rate,v.oxygen_saturation,v.weight_kg,v.bmi,
          NULLIF(left(trim(v.notes),280),'') AS notes
        FROM public.vital_signs v
        WHERE v.patient_id=_patient_id
        ORDER BY v.recorded_at DESC LIMIT 1
      ) x
    ),
    'active_admission', (
      SELECT to_jsonb(x) FROM (
        SELECT a.admitted_at,a.ward,a.bed,a.status,
          NULLIF(left(trim(a.notes),280),'') AS notes
        FROM public.admissions a
        WHERE a.patient_id=_patient_id AND a.status='admitted'
        ORDER BY a.admitted_at DESC LIMIT 1
      ) x
    )
  ) INTO r;

  RETURN r;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_encounter_clinical_context(
  _patient_id UUID,
  _encounter_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user UUID := auth.uid();
  v_patient JSONB;
  v_history JSONB;
  v_vitals JSONB;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (
    public.has_role(v_user,'admin') OR public.has_role(v_user,'practitioner') OR
    public.has_role(v_user,'nurse') OR public.has_role(v_user,'midwife') OR
    public.has_role(v_user,'specialist_nurse')
  ) THEN
    RAISE EXCEPTION 'Clinical access required';
  END IF;

  IF _encounter_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.encounters
    WHERE id=_encounter_id AND patient_id=_patient_id
  ) THEN
    RAISE EXCEPTION 'Encounter does not belong to patient';
  END IF;

  SELECT jsonb_build_object(
    'patient_code',p.patient_code,
    'name',concat_ws(' ',p.first_name,p.last_name),
    'blood_group',p.blood_group,
    'genotype',p.genotype,
    'allergies',NULLIF(trim(p.allergies),''),
    'chronic_conditions',NULLIF(trim(p.chronic_conditions),'')
  ) INTO v_patient
  FROM public.patients p WHERE p.id=_patient_id;

  IF v_patient IS NULL THEN RAISE EXCEPTION 'Patient not found'; END IF;

  SELECT COALESCE(jsonb_agg(x ORDER BY x.created_at DESC),'[]'::jsonb) INTO v_history
  FROM (
    SELECT jsonb_build_object(
      'id',e.id,'created_at',e.created_at,'status',e.status,
      'principal_diagnosis',e.principal_diagnosis,'symptoms',e.symptoms,
      'treatment_plan',e.treatment_plan,
      'diagnoses',COALESCE((
        SELECT jsonb_agg(d.diagnosis ORDER BY d.is_principal DESC,d.created_at DESC)
        FROM public.diagnoses d WHERE d.encounter_id=e.id
      ),'[]'::jsonb)
    ) AS x,e.created_at
    FROM public.encounters e
    WHERE e.patient_id=_patient_id
      AND (_encounter_id IS NULL OR e.id<>_encounter_id)
    ORDER BY e.created_at DESC LIMIT 8
  ) x;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'recorded_at',v.recorded_at,'systolic',v.systolic,'diastolic',v.diastolic,
    'pulse_rate',v.pulse_rate,'temperature',v.temperature,
    'respiratory_rate',v.respiratory_rate,'oxygen_saturation',v.oxygen_saturation,
    'weight_kg',v.weight_kg,'bmi',v.bmi,'priority',v.priority,'notes',v.notes
  ) ORDER BY v.recorded_at DESC),'[]'::jsonb) INTO v_vitals
  FROM (
    SELECT * FROM public.vital_signs
    WHERE patient_id=_patient_id
    ORDER BY recorded_at DESC LIMIT 3
  ) v;

  RETURN jsonb_build_object(
    'patient',v_patient,
    'previous_encounters',v_history,
    'recent_vitals',v_vitals
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_attending_patient_history(UUID,UUID) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.get_encounter_clinical_context(UUID,UUID) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_attending_patient_history(UUID,UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_encounter_clinical_context(UUID,UUID) TO authenticated;
