-- Enforce the same minimum triage measurement invariant for online and offline replay paths.
-- The frontend already requires at least one core measured vital; the database must enforce it too.
ALTER TABLE public.triage_assessments
  DROP CONSTRAINT IF EXISTS triage_assessments_requires_measured_vital;

ALTER TABLE public.triage_assessments
  ADD CONSTRAINT triage_assessments_requires_measured_vital
  CHECK (
    systolic IS NOT NULL OR
    diastolic IS NOT NULL OR
    heart_rate IS NOT NULL OR
    temperature IS NOT NULL OR
    respiratory_rate IS NOT NULL OR
    oxygen_saturation IS NOT NULL OR
    weight_kg IS NOT NULL OR
    height_m IS NOT NULL
  );
