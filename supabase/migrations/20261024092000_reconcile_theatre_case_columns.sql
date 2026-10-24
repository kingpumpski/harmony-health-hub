-- Forward repair for installations where the theatre lifecycle migration is already recorded.
-- Keep legacy aliases and backfill new fields without deleting schedule data.
ALTER TABLE public.theatre_cases
  ADD COLUMN IF NOT EXISTS theatre_name TEXT,
  ADD COLUMN IF NOT EXISTS anesthetist_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS scheduled_start TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS urgency TEXT NOT NULL DEFAULT 'elective',
  ADD COLUMN IF NOT EXISTS encounter_id UUID REFERENCES public.encounters(id) ON DELETE SET NULL;

DO $theatre_column_backfill$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='theatre_cases' AND column_name='theatre'
  ) THEN
    EXECUTE 'UPDATE public.theatre_cases SET theatre_name = COALESCE(theatre_name, theatre)';
  END IF;
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='theatre_cases' AND column_name='anaesthetist_id'
  ) THEN
    EXECUTE 'UPDATE public.theatre_cases SET anesthetist_id = COALESCE(anesthetist_id, anaesthetist_id)';
  END IF;
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='theatre_cases' AND column_name='scheduled_at'
  ) THEN
    EXECUTE 'UPDATE public.theatre_cases SET scheduled_start = COALESCE(scheduled_start, scheduled_at)';
  END IF;
END
$theatre_column_backfill$;

ALTER TABLE public.theatre_cases
  DROP CONSTRAINT IF EXISTS theatre_cases_status_check;
ALTER TABLE public.theatre_cases
  ADD CONSTRAINT theatre_cases_status_check
  CHECK (status IN ('planned','cleared','requested','approved','scheduled','in_progress','completed','cancelled','postponed')) NOT VALID;

ALTER TABLE public.theatre_cases
  DROP CONSTRAINT IF EXISTS theatre_cases_urgency_check;
ALTER TABLE public.theatre_cases
  ADD CONSTRAINT theatre_cases_urgency_check
  CHECK (urgency IN ('emergency','urgent','elective')) NOT VALID;

DO $theatre_constraint_validation$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.theatre_cases
    WHERE status NOT IN ('planned','cleared','requested','approved','scheduled','in_progress','completed','cancelled','postponed')
       OR status IS NULL
  ) THEN
    ALTER TABLE public.theatre_cases VALIDATE CONSTRAINT theatre_cases_status_check;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.theatre_cases
    WHERE urgency NOT IN ('emergency','urgent','elective') OR urgency IS NULL
  ) THEN
    ALTER TABLE public.theatre_cases VALIDATE CONSTRAINT theatre_cases_urgency_check;
  END IF;
END
$theatre_constraint_validation$;

CREATE INDEX IF NOT EXISTS idx_theatre_schedule
  ON public.theatre_cases(scheduled_start, status);
CREATE INDEX IF NOT EXISTS idx_theatre_patient
  ON public.theatre_cases(patient_id, scheduled_start DESC);
