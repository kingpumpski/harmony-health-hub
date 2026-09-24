-- Explicit offline contract for vital signs.
-- This does not open direct table writes: authorization remains server-side in
-- the SECURITY DEFINER workflow and the client supplies a stable UUID so a
-- replay after a lost response becomes a no-op.
CREATE OR REPLACE FUNCTION public.record_patient_vitals_offline(
  _id UUID,
  _patient_id UUID,
  _appointment_id UUID DEFAULT NULL,
  _temperature NUMERIC DEFAULT NULL,
  _pulse INT DEFAULT NULL,
  _systolic INT DEFAULT NULL,
  _diastolic INT DEFAULT NULL,
  _respiratory_rate INT DEFAULT NULL,
  _oxygen_saturation INT DEFAULT NULL,
  _weight_kg NUMERIC DEFAULT NULL,
  _height_cm NUMERIC DEFAULT NULL,
  _notes TEXT DEFAULT NULL,
  _recorded_at TIMESTAMPTZ DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_existing UUID;
  v_bmi NUMERIC;
BEGIN
  IF NOT (
    has_role(auth.uid(),'admin') OR
    has_role(auth.uid(),'practitioner') OR
    has_role(auth.uid(),'nurse') OR
    has_role(auth.uid(),'midwife')
  ) THEN
    RAISE EXCEPTION 'Vital recording is not permitted';
  END IF;

  IF _patient_id IS NULL OR NOT EXISTS (SELECT 1 FROM public.patients WHERE id = _patient_id) THEN
    RAISE EXCEPTION 'Patient not found';
  END IF;
  IF _appointment_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.appointments WHERE id = _appointment_id AND patient_id = _patient_id) THEN
    RAISE EXCEPTION 'Appointment does not belong to patient';
  END IF;

  SELECT id INTO v_existing FROM public.vital_signs WHERE id = _id;
  IF v_existing IS NOT NULL THEN
    RETURN jsonb_build_object('vital_id', v_existing, 'already_recorded', true);
  END IF;

  IF _height_cm IS NOT NULL AND _height_cm > 0 AND _weight_kg IS NOT NULL AND _weight_kg > 0 THEN
    v_bmi := ROUND((_weight_kg / POWER(_height_cm / 100.0, 2))::numeric, 1);
  END IF;

  INSERT INTO public.vital_signs (
    id, patient_id, appointment_id, recorded_by, systolic, diastolic,
    pulse_rate, temperature, respiratory_rate, oxygen_saturation,
    weight_kg, height_cm, bmi, notes, recorded_at
  ) VALUES (
    _id, _patient_id, _appointment_id, auth.uid(), _systolic, _diastolic,
    _pulse, _temperature, _respiratory_rate, _oxygen_saturation,
    _weight_kg, _height_cm, v_bmi, _notes, COALESCE(_recorded_at, now())
  );

  RETURN jsonb_build_object('vital_id', _id, 'already_recorded', false);
END;
$$;

REVOKE ALL ON FUNCTION public.record_patient_vitals_offline(UUID,UUID,UUID,NUMERIC,INT,INT,INT,INT,INT,NUMERIC,NUMERIC,TEXT,TIMESTAMPTZ) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.record_patient_vitals_offline(UUID,UUID,UUID,NUMERIC,INT,INT,INT,INT,INT,NUMERIC,NUMERIC,TEXT,TIMESTAMPTZ) TO authenticated;
