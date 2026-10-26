-- Reconcile the original medication administration table before newer
-- scheduling/status indexes and RPCs rely on the modern MAR columns.
ALTER TABLE public.medication_administrations
  ADD COLUMN IF NOT EXISTS medication_name TEXT,
  ADD COLUMN IF NOT EXISTS route TEXT,
  ADD COLUMN IF NOT EXISTS scheduled_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS status TEXT,
  ADD COLUMN IF NOT EXISTS reason TEXT,
  ADD COLUMN IF NOT EXISTS witnessed_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ;

-- Preserve the actual legacy drug name. Do not substitute a made-up label if
-- both modern and legacy name fields are empty.
UPDATE public.medication_administrations AS mar
SET medication_name = COALESCE(
  NULLIF(btrim(mar.medication_name), ''),
  NULLIF(to_jsonb(mar)->>'drug_name', '')
)
WHERE mar.medication_name IS NULL OR btrim(mar.medication_name) = '';

DO $medication_name_reconcile$
BEGIN
  IF EXISTS (
    SELECT 1 FROM public.medication_administrations
    WHERE medication_name IS NULL OR btrim(medication_name) = ''
  ) THEN
    RAISE EXCEPTION 'Medication administration history contains rows without a verifiable medication name; reconcile from the original dispense record before proceeding.';
  END IF;
END
$medication_name_reconcile$;

-- The legacy relation records administrations, so administered_at is the
-- authoritative event time for those historical rows. Preserve it when the
-- newer scheduled_at field is absent.
UPDATE public.medication_administrations
SET status = 'administered'
WHERE status IS NULL AND administered_at IS NOT NULL;

UPDATE public.medication_administrations
SET scheduled_at = administered_at
WHERE scheduled_at IS NULL AND status = 'administered' AND administered_at IS NOT NULL;

DO $medication_status_reconcile$
BEGIN
  IF EXISTS (
    SELECT 1 FROM public.medication_administrations
    WHERE status IS NULL
       OR status NOT IN ('scheduled','administered','held','refused','omitted','cancelled')
  ) THEN
    RAISE EXCEPTION 'Medication administration history contains rows without a valid status or authoritative administration timestamp; reconcile from verified MAR data before proceeding.';
  END IF;
  IF EXISTS (SELECT 1 FROM public.medication_administrations WHERE scheduled_at IS NULL) THEN
    RAISE EXCEPTION 'Medication administration history contains rows without a verifiable schedule/event timestamp; reconcile before proceeding.';
  END IF;
END
$medication_status_reconcile$;

UPDATE public.medication_administrations
SET updated_at = created_at
WHERE updated_at IS NULL AND created_at IS NOT NULL;

DO $medication_updated_at_reconcile$
BEGIN
  IF EXISTS (SELECT 1 FROM public.medication_administrations WHERE updated_at IS NULL) THEN
    RAISE EXCEPTION 'Medication administration history contains rows without a verifiable update timestamp; reconcile from trusted source data before proceeding.';
  END IF;
END
$medication_updated_at_reconcile$;

ALTER TABLE public.medication_administrations
  ALTER COLUMN medication_name SET NOT NULL,
  ALTER COLUMN status SET DEFAULT 'scheduled',
  ALTER COLUMN status SET NOT NULL,
  ALTER COLUMN scheduled_at SET NOT NULL,
  ALTER COLUMN updated_at SET DEFAULT now(),
  ALTER COLUMN updated_at SET NOT NULL;

ALTER TABLE public.medication_administrations
  DROP CONSTRAINT IF EXISTS medication_administrations_status_valid;
ALTER TABLE public.medication_administrations
  ADD CONSTRAINT medication_administrations_status_valid
  CHECK (status IN ('scheduled','administered','held','refused','omitted','cancelled'));
