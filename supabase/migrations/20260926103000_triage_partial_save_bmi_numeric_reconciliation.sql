-- Reconcile triage persistence: BMI storage, safe numeric ranges, and nullable measurements.
-- Missing measurements remain valid; clinical users are prompted by the UI before saving incomplete assessments.

ALTER TABLE public.triage_assessments
  ADD COLUMN IF NOT EXISTS bmi NUMERIC(5,2);

ALTER TABLE public.triage_assessments
  ALTER COLUMN temperature TYPE NUMERIC(5,2),
  ALTER COLUMN weight_kg TYPE NUMERIC(7,2),
  ALTER COLUMN height_m TYPE NUMERIC(5,2);

CREATE OR REPLACE FUNCTION public.record_triage_assessment(
  _patient_id UUID,
  _systolic INTEGER,
  _diastolic INTEGER,
  _heart_rate INTEGER,
  _temperature NUMERIC,
  _respiratory_rate INTEGER,
  _oxygen_saturation NUMERIC,
  _weight_kg NUMERIC DEFAULT NULL,
  _height_m NUMERIC DEFAULT NULL,
  _pain_score INTEGER DEFAULT NULL,
  _consciousness TEXT DEFAULT NULL,
  _presenting_complaint TEXT DEFAULT NULL,
  _clinical_notes TEXT DEFAULT NULL,
  _priority TEXT DEFAULT 'routine',
  _is_critical BOOLEAN DEFAULT FALSE
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_id UUID;
  v_bmi NUMERIC(5,2);
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
    NULLIF(trim(_clinical_notes), ''), v_priority,
    coalesce(_is_critical, false) OR v_priority = 'critical'
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.record_triage_assessment(UUID, INTEGER, INTEGER, INTEGER, NUMERIC, INTEGER, NUMERIC, NUMERIC, NUMERIC, INTEGER, TEXT, TEXT, TEXT, TEXT, BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.record_triage_assessment(UUID, INTEGER, INTEGER, INTEGER, NUMERIC, INTEGER, NUMERIC, NUMERIC, NUMERIC, INTEGER, TEXT, TEXT, TEXT, TEXT, BOOLEAN) TO authenticated;

COMMENT ON FUNCTION public.record_triage_assessment(UUID, INTEGER, INTEGER, INTEGER, NUMERIC, INTEGER, NUMERIC, NUMERIC, NUMERIC, INTEGER, TEXT, TEXT, TEXT, TEXT, BOOLEAN)
IS 'Server-authoritative triage entry. Optional measurements may be null; BMI is calculated only when valid weight and height are supplied.';
