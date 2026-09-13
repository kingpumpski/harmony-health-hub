-- Final idempotent reconciliation for clinical workflow contracts.
-- This migration intentionally reasserts schema columns and RPCs that are
-- consumed by the frontend so an environment with migration-history drift
-- can converge without introducing a second service or API layer.

ALTER TABLE IF EXISTS public.appointments
  ADD COLUMN IF NOT EXISTS attending_officer_id UUID,
  ADD COLUMN IF NOT EXISTS claimed_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS treatment_status TEXT,
  ADD COLUMN IF NOT EXISTS treatment_notes TEXT,
  ADD COLUMN IF NOT EXISTS started_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS completed_at TIMESTAMPTZ;

ALTER TABLE IF EXISTS public.encounters
  ADD COLUMN IF NOT EXISTS appointment_id UUID,
  ADD COLUMN IF NOT EXISTS practitioner_id UUID,
  ADD COLUMN IF NOT EXISTS symptoms TEXT,
  ADD COLUMN IF NOT EXISTS clerking_notes TEXT,
  ADD COLUMN IF NOT EXISTS principal_diagnosis TEXT,
  ADD COLUMN IF NOT EXISTS treatment_plan TEXT,
  ADD COLUMN IF NOT EXISTS status TEXT,
  ADD COLUMN IF NOT EXISTS completed_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_encounters_appointment_id
  ON public.encounters (appointment_id)
  WHERE appointment_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_encounters_patient_created_at
  ON public.encounters (patient_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_diagnoses_encounter_created_at
  ON public.diagnoses (encounter_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_triage_assessments_patient_created_at
  ON public.triage_assessments (patient_id, created_at DESC);

CREATE OR REPLACE FUNCTION public.create_encounter_workflow(
  _patient_id UUID,
  _symptoms TEXT DEFAULT NULL,
  _clerking_notes TEXT DEFAULT NULL
)
RETURNS public.encounters
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE result public.encounters;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (
    public.has_role(auth.uid(), 'admin'::public.app_role) OR
    public.has_role(auth.uid(), 'practitioner'::public.app_role) OR
    public.has_role(auth.uid(), 'nurse'::public.app_role) OR
    public.has_role(auth.uid(), 'midwife'::public.app_role)
  ) THEN RAISE EXCEPTION 'Only authorized clinical staff may create encounters'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.patients WHERE id = _patient_id) THEN
    RAISE EXCEPTION 'Patient does not exist';
  END IF;
  INSERT INTO public.encounters (patient_id, symptoms, clerking_notes, practitioner_id, status)
  VALUES (_patient_id, NULLIF(trim(_symptoms), ''), NULLIF(trim(_clerking_notes), ''), auth.uid(), 'draft')
  RETURNING * INTO result;
  RETURN result;
END;
$$;

CREATE OR REPLACE FUNCTION public.add_encounter_diagnosis(
  _encounter_id UUID,
  _diagnosis TEXT
)
RETURNS public.diagnoses
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE result public.diagnoses;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (
    public.has_role(auth.uid(), 'admin'::public.app_role) OR
    public.has_role(auth.uid(), 'practitioner'::public.app_role) OR
    public.has_role(auth.uid(), 'nurse'::public.app_role) OR
    public.has_role(auth.uid(), 'midwife'::public.app_role)
  ) THEN RAISE EXCEPTION 'Not authorized to add diagnoses'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.encounters WHERE id = _encounter_id) THEN
    RAISE EXCEPTION 'Encounter does not exist';
  END IF;
  IF NULLIF(trim(_diagnosis), '') IS NULL THEN RAISE EXCEPTION 'Diagnosis is required'; END IF;
  INSERT INTO public.diagnoses (encounter_id, diagnosis, is_principal)
  VALUES (_encounter_id, trim(_diagnosis), false)
  RETURNING * INTO result;
  RETURN result;
END;
$$;

CREATE OR REPLACE FUNCTION public.set_principal_diagnosis(
  _encounter_id UUID,
  _diagnosis_id UUID
)
RETURNS public.diagnoses
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE result public.diagnoses;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (
    public.has_role(auth.uid(), 'admin'::public.app_role) OR
    public.has_role(auth.uid(), 'practitioner'::public.app_role) OR
    public.has_role(auth.uid(), 'nurse'::public.app_role) OR
    public.has_role(auth.uid(), 'midwife'::public.app_role)
  ) THEN RAISE EXCEPTION 'Not authorized to set principal diagnosis'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.diagnoses
    WHERE id = _diagnosis_id AND encounter_id = _encounter_id
  ) THEN RAISE EXCEPTION 'Diagnosis does not belong to encounter'; END IF;
  UPDATE public.diagnoses SET is_principal = false WHERE encounter_id = _encounter_id;
  UPDATE public.diagnoses
  SET is_principal = true
  WHERE id = _diagnosis_id
  RETURNING * INTO result;
  UPDATE public.encounters
  SET principal_diagnosis = result.diagnosis,
      updated_at = COALESCE(updated_at, now())
  WHERE id = _encounter_id;
  RETURN result;
END;
$$;

CREATE OR REPLACE FUNCTION public.remove_encounter_diagnosis(_diagnosis_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (
    public.has_role(auth.uid(), 'admin'::public.app_role) OR
    public.has_role(auth.uid(), 'practitioner'::public.app_role) OR
    public.has_role(auth.uid(), 'nurse'::public.app_role) OR
    public.has_role(auth.uid(), 'midwife'::public.app_role)
  ) THEN RAISE EXCEPTION 'Not authorized to remove diagnoses'; END IF;
  DELETE FROM public.diagnoses WHERE id = _diagnosis_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_encounter_prescription(
  _encounter_id UUID,
  _medication TEXT,
  _dosage TEXT DEFAULT NULL,
  _frequency TEXT DEFAULT NULL,
  _duration TEXT DEFAULT NULL
)
RETURNS public.prescriptions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE result public.prescriptions; patient_id_value UUID;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (
    public.has_role(auth.uid(), 'admin'::public.app_role) OR
    public.has_role(auth.uid(), 'practitioner'::public.app_role) OR
    public.has_role(auth.uid(), 'nurse'::public.app_role) OR
    public.has_role(auth.uid(), 'midwife'::public.app_role)
  ) THEN RAISE EXCEPTION 'Not authorized to prescribe'; END IF;
  SELECT patient_id INTO patient_id_value FROM public.encounters WHERE id = _encounter_id;
  IF patient_id_value IS NULL THEN RAISE EXCEPTION 'Encounter does not exist'; END IF;
  IF NULLIF(trim(_medication), '') IS NULL THEN RAISE EXCEPTION 'Medication is required'; END IF;
  INSERT INTO public.prescriptions (
    encounter_id, patient_id, prescribed_by, medication, dosage, frequency, duration
  ) VALUES (
    _encounter_id, patient_id_value, auth.uid(), trim(_medication),
    NULLIF(trim(_dosage), ''), NULLIF(trim(_frequency), ''), NULLIF(trim(_duration), '')
  )
  RETURNING * INTO result;
  RETURN result;
END;
$$;

CREATE OR REPLACE FUNCTION public.complete_encounter_workflow(_encounter_id UUID)
RETURNS public.encounters
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE result public.encounters;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (
    public.has_role(auth.uid(), 'admin'::public.app_role) OR
    public.has_role(auth.uid(), 'practitioner'::public.app_role) OR
    public.has_role(auth.uid(), 'nurse'::public.app_role) OR
    public.has_role(auth.uid(), 'midwife'::public.app_role)
  ) THEN RAISE EXCEPTION 'Not authorized to complete encounters'; END IF;

  SELECT * INTO result
  FROM public.encounters
  WHERE id = _encounter_id
  FOR UPDATE;

  IF result.id IS NULL THEN RAISE EXCEPTION 'Encounter does not exist'; END IF;
  IF result.status = 'completed' THEN RETURN result; END IF;
  IF result.principal_diagnosis IS NULL OR NULLIF(trim(result.principal_diagnosis), '') IS NULL THEN
    RAISE EXCEPTION 'Principal diagnosis required';
  END IF;

  UPDATE public.encounters
  SET status = 'completed',
      completed_at = COALESCE(completed_at, now()),
      updated_at = COALESCE(updated_at, now())
  WHERE id = _encounter_id
  RETURNING * INTO result;

  RETURN result;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_encounter_clinical_context(
  _patient_id UUID,
  _encounter_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
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
      'diagnoses', COALESCE((
        SELECT jsonb_agg(d.diagnosis ORDER BY d.is_principal DESC, d.created_at DESC)
        FROM public.diagnoses d WHERE d.encounter_id = e.id
      ), '[]'::jsonb)
    ) AS x, e.created_at
    FROM public.encounters e
    WHERE e.patient_id = _patient_id
      AND (_encounter_id IS NULL OR e.id <> _encounter_id)
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
  FROM (
    SELECT * FROM public.vital_signs
    WHERE patient_id = _patient_id
    ORDER BY recorded_at DESC LIMIT 3
  ) v;

  RETURN jsonb_build_object(
    'patient', v_patient,
    'previous_encounters', v_history,
    'recent_vitals', v_vitals
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.get_patient_bmi_context(_patient_id UUID)
RETURNS TABLE(
  bmi NUMERIC,
  category TEXT,
  weight_kg NUMERIC,
  height_m NUMERIC,
  recorded_at TIMESTAMPTZ
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (
    public.has_role(auth.uid(),'admin'::public.app_role) OR
    public.has_role(auth.uid(),'practitioner'::public.app_role) OR
    public.has_role(auth.uid(),'nurse'::public.app_role) OR
    public.has_role(auth.uid(),'midwife'::public.app_role) OR
    public.has_role(auth.uid(),'pharmacist'::public.app_role)
  ) THEN RAISE EXCEPTION 'Clinical access required'; END IF;

  RETURN QUERY
  SELECT t.bmi, public.get_bmi_category(t.bmi), t.weight_kg, t.height_m, t.created_at
  FROM public.triage_assessments t
  WHERE t.patient_id = _patient_id AND t.bmi IS NOT NULL
  ORDER BY t.created_at DESC LIMIT 1;
END;
$$;

REVOKE ALL ON FUNCTION public.create_encounter_workflow(UUID,TEXT,TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.add_encounter_diagnosis(UUID,TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.set_principal_diagnosis(UUID,UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.remove_encounter_diagnosis(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_encounter_prescription(UUID,TEXT,TEXT,TEXT,TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.complete_encounter_workflow(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_encounter_clinical_context(UUID,UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_patient_bmi_context(UUID) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.create_encounter_workflow(UUID,TEXT,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.add_encounter_diagnosis(UUID,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_principal_diagnosis(UUID,UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.remove_encounter_diagnosis(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_encounter_prescription(UUID,TEXT,TEXT,TEXT,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.complete_encounter_workflow(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_encounter_clinical_context(UUID,UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_patient_bmi_context(UUID) TO authenticated;

NOTIFY pgrst, 'reload schema';
