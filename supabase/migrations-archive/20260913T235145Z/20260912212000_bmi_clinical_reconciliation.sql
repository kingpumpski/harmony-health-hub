-- Clinical BMI reconciliation.
-- BMI is derived from the latest recorded weight and height and is exposed to
-- clinicians as a decision-support measurement. It does not prescribe therapy.

ALTER TABLE public.triage_assessments
  ADD COLUMN IF NOT EXISTS bmi NUMERIC(5,2);

CREATE OR REPLACE FUNCTION public.calculate_triage_bmi()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.weight_kg IS NOT NULL AND NEW.height_m IS NOT NULL AND NEW.height_m > 0 THEN
    NEW.bmi := ROUND((NEW.weight_kg / (NEW.height_m * NEW.height_m))::numeric, 2);
  ELSE
    NEW.bmi := NULL;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_calculate_triage_bmi ON public.triage_assessments;
CREATE TRIGGER trg_calculate_triage_bmi
BEFORE INSERT OR UPDATE OF weight_kg, height_m ON public.triage_assessments
FOR EACH ROW
EXECUTE FUNCTION public.calculate_triage_bmi();

UPDATE public.triage_assessments
SET bmi = CASE
  WHEN weight_kg IS NOT NULL AND height_m IS NOT NULL AND height_m > 0
    THEN ROUND((weight_kg / (height_m * height_m))::numeric, 2)
  ELSE NULL
END
WHERE bmi IS DISTINCT FROM CASE
  WHEN weight_kg IS NOT NULL AND height_m IS NOT NULL AND height_m > 0
    THEN ROUND((weight_kg / (height_m * height_m))::numeric, 2)
  ELSE NULL
END;

CREATE INDEX IF NOT EXISTS idx_triage_patient_bmi_time
  ON public.triage_assessments(patient_id, created_at DESC)
  WHERE bmi IS NOT NULL;

CREATE OR REPLACE FUNCTION public.get_bmi_category(_bmi NUMERIC)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN _bmi IS NULL OR _bmi <= 0 THEN 'unavailable'
    WHEN _bmi < 18.5 THEN 'underweight'
    WHEN _bmi < 25 THEN 'healthy range'
    WHEN _bmi < 30 THEN 'overweight'
    ELSE 'obesity range'
  END;
$$;

REVOKE ALL ON FUNCTION public.get_bmi_category(NUMERIC) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_bmi_category(NUMERIC) TO authenticated;

-- Keep the BMI calculation server-authoritative while retaining the existing
-- triage RPC contract used by the application.
REVOKE EXECUTE ON FUNCTION public.calculate_triage_bmi() FROM PUBLIC;
