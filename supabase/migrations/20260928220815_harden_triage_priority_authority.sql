-- Remove the legacy client-controlled _is_critical argument from the live triage RPC.
-- Priority remains the only client-supplied escalation field; the server derives is_critical.
DROP FUNCTION IF EXISTS public.record_triage_assessment(uuid,integer,integer,integer,numeric,integer,numeric,numeric,numeric,integer,text,text,text,text,boolean);

CREATE OR REPLACE FUNCTION public.record_triage_assessment(
  _patient_id UUID,
  _systolic INTEGER DEFAULT NULL,
  _diastolic INTEGER DEFAULT NULL,
  _heart_rate INTEGER DEFAULT NULL,
  _temperature NUMERIC DEFAULT NULL,
  _respiratory_rate INTEGER DEFAULT NULL,
  _oxygen_saturation NUMERIC DEFAULT NULL,
  _weight_kg NUMERIC DEFAULT NULL,
  _height_m NUMERIC DEFAULT NULL,
  _pain_score INTEGER DEFAULT NULL,
  _consciousness TEXT DEFAULT NULL,
  _presenting_complaint TEXT DEFAULT NULL,
  _clinical_notes TEXT DEFAULT NULL,
  _priority TEXT DEFAULT 'routine'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id UUID;
  v_bmi NUMERIC(7,2);
  v_priority TEXT := lower(trim(coalesce(_priority, 'routine')));
BEGIN
  IF auth.uid() IS NULL OR NOT (
    public.has_role(auth.uid(),'admin') OR
    public.has_role(auth.uid(),'practitioner') OR
    public.has_role(auth.uid(),'nurse') OR
    public.has_role(auth.uid(),'midwife') OR
    public.has_role(auth.uid(),'specialist_nurse')
  ) THEN
    RAISE EXCEPTION 'Not authorized to record triage';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.patients WHERE id = _patient_id) THEN
    RAISE EXCEPTION 'Patient not found';
  END IF;

  IF v_priority NOT IN ('critical','urgent','moderate','routine') THEN
    RAISE EXCEPTION 'Invalid triage priority';
  END IF;

  IF _pain_score IS NOT NULL AND (_pain_score < 0 OR _pain_score > 10) THEN
    RAISE EXCEPTION 'Pain score must be between 0 and 10';
  END IF;
  IF _systolic IS NOT NULL AND (_systolic < 0 OR _systolic > 400) THEN
    RAISE EXCEPTION 'SBP must be between 0 and 400 mmHg';
  END IF;
  IF _diastolic IS NOT NULL AND (_diastolic < 0 OR _diastolic > 300) THEN
    RAISE EXCEPTION 'DBP must be between 0 and 300 mmHg';
  END IF;
  IF _heart_rate IS NOT NULL AND (_heart_rate < 0 OR _heart_rate > 300) THEN
    RAISE EXCEPTION 'Heart rate must be between 0 and 300 bpm';
  END IF;
  IF _temperature IS NOT NULL AND (_temperature < 20 OR _temperature > 50) THEN
    RAISE EXCEPTION 'Temperature must be between 20 and 50 °C';
  END IF;
  IF _respiratory_rate IS NOT NULL AND (_respiratory_rate < 0 OR _respiratory_rate > 100) THEN
    RAISE EXCEPTION 'Respiratory rate must be between 0 and 100 per minute';
  END IF;
  IF _oxygen_saturation IS NOT NULL AND (_oxygen_saturation < 0 OR _oxygen_saturation > 100) THEN
    RAISE EXCEPTION 'Oxygen saturation must be between 0 and 100 percent';
  END IF;
  IF _weight_kg IS NOT NULL AND (_weight_kg <= 0 OR _weight_kg > 500) THEN
    RAISE EXCEPTION 'Weight must be greater than 0 and no more than 500 kg';
  END IF;
  IF _height_m IS NOT NULL AND (_height_m <= 0 OR _height_m > 3) THEN
    RAISE EXCEPTION 'Height must be entered in metres and be between 0 and 3 m';
  END IF;

  IF _weight_kg IS NOT NULL AND _height_m IS NOT NULL AND _weight_kg > 0 AND _height_m > 0 THEN
    v_bmi := round((_weight_kg / power(_height_m, 2))::numeric, 2);
  END IF;

  INSERT INTO public.triage_assessments (
    patient_id, recorded_by, systolic, diastolic, heart_rate, temperature,
    respiratory_rate, oxygen_saturation, weight_kg, height_m, bmi, pain_score,
    consciousness, presenting_complaint, clinical_notes, priority, is_critical
  )
  VALUES (
    _patient_id, auth.uid(), _systolic, _diastolic, _heart_rate, _temperature,
    _respiratory_rate, _oxygen_saturation, _weight_kg, _height_m, v_bmi, _pain_score,
    NULLIF(trim(_consciousness), ''), NULLIF(trim(_presenting_complaint), ''),
    NULLIF(trim(_clinical_notes), ''), v_priority, v_priority = 'critical'
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.record_triage_assessment(UUID, INTEGER, INTEGER, INTEGER, NUMERIC, INTEGER, NUMERIC, NUMERIC, NUMERIC, INTEGER, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.record_triage_assessment(UUID, INTEGER, INTEGER, INTEGER, NUMERIC, INTEGER, NUMERIC, NUMERIC, NUMERIC, INTEGER, TEXT, TEXT, TEXT, TEXT) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.record_triage_assessment(UUID, INTEGER, INTEGER, INTEGER, NUMERIC, INTEGER, NUMERIC, NUMERIC, NUMERIC, INTEGER, TEXT, TEXT, TEXT, TEXT) FROM anon;
