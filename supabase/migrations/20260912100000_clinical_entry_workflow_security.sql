-- Consolidate front-end clinical entry points behind server-authoritative RPCs.
-- Existing tables and data are preserved; this migration only adds guarded entry functions.

CREATE OR REPLACE FUNCTION public.create_appointment_workflow(
  _patient_id UUID,
  _scheduled_at TIMESTAMPTZ,
  _department TEXT,
  _reason TEXT DEFAULT NULL
)
RETURNS public.appointments
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  result public.appointments;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (
    public.has_role(auth.uid(), 'admin'::public.app_role)
    OR public.has_role(auth.uid(), 'front_desk'::public.app_role)
    OR public.has_role(auth.uid(), 'practitioner'::public.app_role)
    OR public.has_role(auth.uid(), 'nurse'::public.app_role)
    OR public.has_role(auth.uid(), 'midwife'::public.app_role)
    OR public.has_role(auth.uid(), 'specialist_nurse'::public.app_role)
  ) THEN
    RAISE EXCEPTION 'You are not authorized to schedule appointments';
  END IF;
  IF _patient_id IS NULL THEN RAISE EXCEPTION 'Patient is required'; END IF;
  IF _scheduled_at IS NULL THEN RAISE EXCEPTION 'Appointment time is required'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.patients WHERE id = _patient_id) THEN
    RAISE EXCEPTION 'Patient does not exist';
  END IF;

  INSERT INTO public.appointments (
    patient_id, scheduled_at, reason, department, status, treatment_status, created_by
  )
  VALUES (
    _patient_id, _scheduled_at, NULLIF(trim(_reason), ''), NULLIF(trim(_department), ''),
    'scheduled', 'scheduled', auth.uid()
  )
  RETURNING * INTO result;

  RETURN result;
END;
$$;

CREATE OR REPLACE FUNCTION public.record_triage_assessment(
  _patient_id UUID,
  _systolic NUMERIC,
  _diastolic NUMERIC,
  _heart_rate NUMERIC,
  _temperature NUMERIC,
  _respiratory_rate NUMERIC,
  _oxygen_saturation NUMERIC,
  _weight_kg NUMERIC DEFAULT NULL,
  _height_m NUMERIC DEFAULT NULL,
  _pain_score INTEGER DEFAULT 0,
  _consciousness TEXT DEFAULT 'Alert',
  _presenting_complaint TEXT DEFAULT NULL,
  _clinical_notes TEXT DEFAULT NULL,
  _priority TEXT DEFAULT 'routine'
)
RETURNS public.triage_assessments
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  result public.triage_assessments;
  normalized_priority TEXT := lower(trim(_priority));
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (
    public.has_role(auth.uid(), 'admin'::public.app_role)
    OR public.has_role(auth.uid(), 'practitioner'::public.app_role)
    OR public.has_role(auth.uid(), 'nurse'::public.app_role)
    OR public.has_role(auth.uid(), 'midwife'::public.app_role)
    OR public.has_role(auth.uid(), 'specialist_nurse'::public.app_role)
  ) THEN
    RAISE EXCEPTION 'Only authorized clinical staff may record triage';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.patients WHERE id = _patient_id) THEN
    RAISE EXCEPTION 'Patient does not exist';
  END IF;
  IF normalized_priority NOT IN ('critical','urgent','moderate','routine') THEN
    RAISE EXCEPTION 'Invalid triage priority';
  END IF;
  IF _pain_score < 0 OR _pain_score > 10 THEN RAISE EXCEPTION 'Pain score must be between 0 and 10'; END IF;
  IF _oxygen_saturation < 0 OR _oxygen_saturation > 100 THEN RAISE EXCEPTION 'Oxygen saturation must be between 0 and 100'; END IF;
  IF _height_m IS NOT NULL AND _height_m <= 0 THEN RAISE EXCEPTION 'Height must be greater than zero'; END IF;
  IF _weight_kg IS NOT NULL AND _weight_kg <= 0 THEN RAISE EXCEPTION 'Weight must be greater than zero'; END IF;

  INSERT INTO public.triage_assessments (
    patient_id, recorded_by, systolic, diastolic, heart_rate, temperature,
    respiratory_rate, oxygen_saturation, weight_kg, height_m, pain_score,
    consciousness, presenting_complaint, clinical_notes, priority, is_critical
  )
  VALUES (
    _patient_id, auth.uid(), _systolic, _diastolic, _heart_rate, _temperature,
    _respiratory_rate, _oxygen_saturation, _weight_kg, _height_m, _pain_score,
    NULLIF(trim(_consciousness), ''), NULLIF(trim(_presenting_complaint), ''),
    NULLIF(trim(_clinical_notes), ''), normalized_priority, normalized_priority = 'critical'
  )
  RETURNING * INTO result;

  RETURN result;
END;
$$;

REVOKE ALL ON FUNCTION public.create_appointment_workflow(UUID, TIMESTAMPTZ, TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.record_triage_assessment(UUID, NUMERIC, NUMERIC, NUMERIC, NUMERIC, NUMERIC, NUMERIC, NUMERIC, NUMERIC, INTEGER, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_appointment_workflow(UUID, TIMESTAMPTZ, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_triage_assessment(UUID, NUMERIC, NUMERIC, NUMERIC, NUMERIC, NUMERIC, NUMERIC, NUMERIC, NUMERIC, INTEGER, TEXT, TEXT, TEXT, TEXT) TO authenticated;

COMMENT ON FUNCTION public.create_appointment_workflow(UUID, TIMESTAMPTZ, TEXT, TEXT) IS 'Server-authoritative appointment creation for authorized facility staff.';
COMMENT ON FUNCTION public.record_triage_assessment(UUID, NUMERIC, NUMERIC, NUMERIC, NUMERIC, NUMERIC, NUMERIC, NUMERIC, NUMERIC, INTEGER, TEXT, TEXT, TEXT, TEXT) IS 'Server-authoritative triage entry for authorized clinical staff.';
