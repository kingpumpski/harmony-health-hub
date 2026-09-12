-- Keep the attending officer's safety-critical history in the encounter workspace.
-- This is intentionally a concise clinical summary, not a replacement for the full chart.

CREATE OR REPLACE FUNCTION public.get_attending_patient_history(_patient_id UUID, _current_encounter_id UUID DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _allowed BOOLEAN;
  _result JSONB;
BEGIN
  SELECT EXISTS (
    SELECT 1
    FROM public.user_roles ur
    WHERE ur.user_id = auth.uid()
      AND ur.role::text IN ('admin','practitioner','nurse','midwife','specialist_nurse')
  ) INTO _allowed;

  IF auth.uid() IS NULL OR NOT _allowed THEN
    RAISE EXCEPTION 'Not authorized to view attending clinical history';
  END IF;

  IF _patient_id IS NULL THEN
    RAISE EXCEPTION 'Patient is required';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.patients WHERE id = _patient_id) THEN
    RAISE EXCEPTION 'Patient not found';
  END IF;

  SELECT jsonb_build_object(
    'patient', (
      SELECT jsonb_build_object(
        'id', p.id,
        'patient_code', p.patient_code,
        'name', concat_ws(' ', p.first_name, p.last_name),
        'blood_group', p.blood_group,
        'genotype', p.genotype,
        'allergies', NULLIF(trim(p.allergies), ''),
        'chronic_conditions', NULLIF(trim(p.chronic_conditions), '')
      )
      FROM public.patients p
      WHERE p.id = _patient_id
    ),
    'prior_encounters', COALESCE((
      SELECT jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC)
      FROM (
        SELECT
          e.id,
          e.created_at,
          e.status,
          NULLIF(trim(e.principal_diagnosis), '') AS principal_diagnosis,
          COALESCE((
            SELECT string_agg(d.diagnosis, ', ' ORDER BY d.is_principal DESC, d.created_at ASC)
            FROM public.diagnoses d
            WHERE d.encounter_id = e.id
          ), NULL) AS diagnoses,
          NULLIF(left(trim(e.symptoms), 280), '') AS presenting_symptoms,
          NULLIF(left(trim(e.treatment_plan), 360), '') AS prior_treatment_plan
        FROM public.encounters e
        WHERE e.patient_id = _patient_id
          AND (_current_encounter_id IS NULL OR e.id <> _current_encounter_id)
        ORDER BY e.created_at DESC
        LIMIT 8
      ) x
    ), '[]'::jsonb),
    'major_diagnoses', COALESCE((
      SELECT jsonb_agg(to_jsonb(x) ORDER BY x.last_seen DESC)
      FROM (
        SELECT
          COALESCE(NULLIF(trim(d.diagnosis), ''), NULLIF(trim(e.principal_diagnosis), '')) AS diagnosis,
          max(e.created_at) AS last_seen,
          count(*)::int AS occurrences
        FROM public.diagnoses d
        JOIN public.encounters e ON e.id = d.encounter_id
        WHERE e.patient_id = _patient_id
          AND (_current_encounter_id IS NULL OR e.id <> _current_encounter_id)
          AND NULLIF(trim(d.diagnosis), '') IS NOT NULL
        GROUP BY COALESCE(NULLIF(trim(d.diagnosis), ''), NULLIF(trim(e.principal_diagnosis), ''))
        ORDER BY last_seen DESC
        LIMIT 12
      ) x
    ), '[]'::jsonb),
    'abnormal_labs', COALESCE((
      SELECT jsonb_agg(to_jsonb(x) ORDER BY x.entered_at DESC)
      FROM (
        SELECT
          lo.id AS lab_order_id,
          lo.test_name,
          lo.test_category,
          lr.interpretation,
          lr.result_data,
          lr.entered_at
        FROM public.lab_orders lo
        JOIN public.lab_results lr ON lr.lab_order_id = lo.id
        WHERE lo.patient_id = _patient_id
          AND lr.is_abnormal = true
        ORDER BY lr.entered_at DESC
        LIMIT 8
      ) x
    ), '[]'::jsonb),
    'recent_prescriptions', COALESCE((
      SELECT jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC)
      FROM (
        SELECT
          pr.medication,
          pr.dosage,
          pr.frequency,
          pr.duration,
          pr.status,
          pr.created_at
        FROM public.prescriptions pr
        WHERE pr.patient_id = _patient_id
          AND pr.status <> 'cancelled'
        ORDER BY pr.created_at DESC
        LIMIT 8
      ) x
    ), '[]'::jsonb),
    'latest_triage', (
      SELECT to_jsonb(x)
      FROM (
        SELECT
          v.recorded_at,
          v.priority,
          v.systolic,
          v.diastolic,
          v.pulse_rate,
          v.temperature,
          v.respiratory_rate,
          v.oxygen_saturation,
          v.weight_kg,
          v.bmi,
          NULLIF(left(trim(v.notes), 280), '') AS notes
        FROM public.vital_signs v
        WHERE v.patient_id = _patient_id
        ORDER BY v.recorded_at DESC
        LIMIT 1
      ) x
    ),
    'active_admission', (
      SELECT to_jsonb(x)
      FROM (
        SELECT
          a.admitted_at,
          a.ward,
          a.bed,
          a.status,
          a.diagnosis,
          NULLIF(left(trim(a.notes), 280), '') AS notes
        FROM public.admissions a
        WHERE a.patient_id = _patient_id
          AND a.status = 'admitted'
        ORDER BY a.admitted_at DESC
        LIMIT 1
      ) x
    )
  ) INTO _result;

  RETURN _result;
END;
$$;

REVOKE ALL ON FUNCTION public.get_attending_patient_history(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_attending_patient_history(UUID, UUID) TO authenticated;
