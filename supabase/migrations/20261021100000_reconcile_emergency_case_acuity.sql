-- Forward repair for emergency_cases installations where the original migration is recorded.
ALTER TABLE public.emergency_cases
  ADD COLUMN IF NOT EXISTS acuity TEXT NOT NULL DEFAULT 'urgent';

DO $emergency_acuity$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.emergency_cases'::regclass
      AND conname = 'emergency_cases_acuity_check'
  ) THEN
    ALTER TABLE public.emergency_cases
      ADD CONSTRAINT emergency_cases_acuity_check
      CHECK (acuity IN ('resuscitation','emergency','urgent','less_urgent','non_urgent')) NOT VALID;
  END IF;
END
$emergency_acuity$;
