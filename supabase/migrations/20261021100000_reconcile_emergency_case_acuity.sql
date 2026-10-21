-- Forward-only compatibility for databases where the original HIMS migration
-- is already recorded as applied but emergency_cases predates the acuity field.
ALTER TABLE public.emergency_cases
  ADD COLUMN IF NOT EXISTS acuity TEXT NOT NULL DEFAULT 'urgent';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.emergency_cases'::regclass
      AND conname = 'emergency_cases_acuity_check'
  ) THEN
    ALTER TABLE public.emergency_cases
      ADD CONSTRAINT emergency_cases_acuity_check
      CHECK (acuity IN ('resuscitation','emergency','urgent','less_urgent','non_urgent'));
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_emergency_queue
  ON public.emergency_cases(status, acuity, arrival_time);

NOTIFY pgrst, 'reload schema';
