-- Reconcile the original pharmacy MAR table before newer indexes and RPCs
-- assume the scheduling/status fields introduced by the modern MAR contract.
ALTER TABLE public.medication_administrations
  ADD COLUMN IF NOT EXISTS medication_name TEXT,
  ADD COLUMN IF NOT EXISTS route TEXT,
  ADD COLUMN IF NOT EXISTS scheduled_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS status TEXT,
  ADD COLUMN IF NOT EXISTS reason TEXT,
  ADD COLUMN IF NOT EXISTS witnessed_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT now();

-- Preserve old dispense rows. The historic table called this field drug_name;
-- JSON extraction keeps this migration valid whether that legacy column remains.
UPDATE public.medication_administrations AS mar
SET medication_name = COALESCE(
  NULLIF(btrim(mar.medication_name), ''),
  NULLIF(to_jsonb(mar)->>'drug_name', ''),
  'Legacy medication'
)
WHERE mar.medication_name IS NULL OR btrim(mar.medication_name) = '';

UPDATE public.medication_administrations
SET status = CASE
  WHEN administered_at IS NOT NULL THEN 'administered'
  ELSE 'scheduled'
END
WHERE status IS NULL
   OR status NOT IN ('scheduled','administered','held','refused','omitted','cancelled');

UPDATE public.medication_administrations
SET scheduled_at = COALESCE(scheduled_at, administered_at, created_at)
WHERE scheduled_at IS NULL;

UPDATE public.medication_administrations
SET updated_at = COALESCE(updated_at, created_at, now())
WHERE updated_at IS NULL;

ALTER TABLE public.medication_administrations
  ALTER COLUMN medication_name SET NOT NULL,
  ALTER COLUMN status SET DEFAULT 'scheduled',
  ALTER COLUMN status SET NOT NULL,
  ALTER COLUMN updated_at SET DEFAULT now(),
  ALTER COLUMN updated_at SET NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'public.medication_administrations'::regclass
      AND conname = 'medication_administrations_status_valid'
  ) THEN
    ALTER TABLE public.medication_administrations
      ADD CONSTRAINT medication_administrations_status_valid
      CHECK (status IN ('scheduled','administered','held','refused','omitted','cancelled'));
  END IF;
END;
$$;
