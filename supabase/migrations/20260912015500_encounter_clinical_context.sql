-- Clinical encounter safety context.
-- Keeps high-value patient warnings available to an attending officer without
-- requiring navigation away from the active encounter.
CREATE OR REPLACE FUNCTION public.get_encounter_clinical_context(_patient_id UUID, _encounter_id UUID DEFAULT NULL)
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
    public.has_role(v_user,'nurse') OR public.has_role(v_user,'midwife')
  ) THEN RAISE EXCEPTION 'Clinical access required'; END IF;

  SELECT jsonb_build_object(
    'patient_code', p.patient_code,
    'name', concat_ws(' ', p.first_name, p.last_name),
    'blood_group', p.blood_group,
    'genotype', p.genotype,
    'allergies', NULLIF(trim(p.allergies), ''),
    'chronic_conditions', NULLIF(trim(p.chronic_conditions), '')
  ) INTO v_patient
  FROM public.patients p WHERE p.id = _patient_id;

  IF v_patient IS NULL THEN RAISE EXCEPTION 'Patient not found'; END IF;

  SELECT COALESCE(jsonb_agg(x ORDER BY x.created_at DESC), '[]'::jsonb) INTO v_history
  FROM (
    SELECT jsonb_build_object(
      'id', e.id,
      'created_at', e.created_at,
      'status', e.status,
      'principal_diagnosis', e.principal_diagnosis,
      'symptoms', e.symptoms,
      'treatment_plan', e.treatment_plan,
      'diagnoses', COALESCE((SELECT jsonb_agg(d.diagnosis ORDER BY d.is_principal DESC, d.created_at DESC) FROM public.diagnoses d WHERE d.encounter_id = e.id), '[]'::jsonb)
    ) AS x, e.created_at
    FROM public.encounters e
    WHERE e.patient_id = _patient_id AND (_encounter_id IS NULL OR e.id <> _encounter_id)
    ORDER BY e.created_at DESC LIMIT 8
  ) x;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'recorded_at', v.recorded_at,
    'systolic', v.systolic,
    'diastolic', v.diastolic,
    'pulse_rate', v.pulse_rate,
    'temperature', v.temperature,
    'respiratory_rate', v.respiratory_rate,
    'oxygen_saturation', v.oxygen_saturation,
    'weight_kg', v.weight_kg,
    'bmi', v.bmi,
    'priority', v.priority,
    'notes', v.notes
  ) ORDER BY v.recorded_at DESC), '[]'::jsonb) INTO v_vitals
  FROM (SELECT * FROM public.vital_signs WHERE patient_id = _patient_id ORDER BY recorded_at DESC LIMIT 3) v;

  RETURN jsonb_build_object('patient', v_patient, 'previous_encounters', v_history, 'recent_vitals', v_vitals);
END;
$$;

REVOKE ALL ON FUNCTION public.get_encounter_clinical_context(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_encounter_clinical_context(UUID, UUID) TO authenticated;
