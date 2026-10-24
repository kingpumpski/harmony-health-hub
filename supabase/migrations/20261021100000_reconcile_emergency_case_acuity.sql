-- Forward repair for installations where the original emergency-care migrations
-- are already recorded. Reconcile both the canonical timestamp and acuity fields
-- without dropping legacy columns or losing known triage chronology.
ALTER TABLE public.emergency_cases
  ADD COLUMN IF NOT EXISTS arrival_time timestamptz,
  ADD COLUMN IF NOT EXISTS acuity text;

DO $emergency_legacy_reconcile$
DECLARE
  v_has_arrival_at boolean;
  v_has_created_at boolean;
  v_has_triage_priority boolean;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'emergency_cases' AND column_name = 'arrival_at'
  ) INTO v_has_arrival_at;
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'emergency_cases' AND column_name = 'created_at'
  ) INTO v_has_created_at;
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'emergency_cases' AND column_name = 'triage_priority'
  ) INTO v_has_triage_priority;

  IF v_has_arrival_at THEN
    EXECUTE 'UPDATE public.emergency_cases SET arrival_time = arrival_at WHERE arrival_time IS NULL';
  END IF;
  IF v_has_created_at THEN
    EXECUTE 'UPDATE public.emergency_cases SET arrival_time = created_at WHERE arrival_time IS NULL';
  END IF;
  UPDATE public.emergency_cases SET arrival_time = now() WHERE arrival_time IS NULL;
  ALTER TABLE public.emergency_cases ALTER COLUMN arrival_time SET DEFAULT now();
  ALTER TABLE public.emergency_cases ALTER COLUMN arrival_time SET NOT NULL;

  IF v_has_triage_priority THEN
    EXECUTE $backfill$
      UPDATE public.emergency_cases
      SET acuity = CASE lower(trim(triage_priority))
        WHEN 'critical' THEN 'emergency'
        WHEN 'urgent' THEN 'urgent'
        WHEN 'moderate' THEN 'less_urgent'
        WHEN 'routine' THEN 'non_urgent'
        ELSE COALESCE(acuity, 'urgent')
      END
      WHERE acuity IS NULL
         OR (acuity = 'urgent' AND lower(trim(triage_priority)) <> 'urgent')
    $backfill$;
  END IF;

  UPDATE public.emergency_cases SET acuity = 'urgent' WHERE acuity IS NULL;
  ALTER TABLE public.emergency_cases ALTER COLUMN acuity SET DEFAULT 'urgent';
  ALTER TABLE public.emergency_cases ALTER COLUMN acuity SET NOT NULL;

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
$emergency_legacy_reconcile$;
