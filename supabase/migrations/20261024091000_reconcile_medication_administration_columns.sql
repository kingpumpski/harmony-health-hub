-- Forward repair for installations where the original MAR migration is already recorded.
-- Preserve legacy drug names and timestamps; avoid inferring administration from a
-- legacy administered_at default when administered_by is absent.
ALTER TABLE public.medication_administrations
  ADD COLUMN IF NOT EXISTS medication_name TEXT,
  ADD COLUMN IF NOT EXISTS route TEXT,
  ADD COLUMN IF NOT EXISTS scheduled_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS status TEXT,
  ADD COLUMN IF NOT EXISTS witnessed_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS reason TEXT,
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ;

UPDATE public.medication_administrations
SET medication_name = COALESCE(NULLIF(BTRIM(medication_name), ''), NULLIF(BTRIM(drug_name), '')),
    status = COALESCE(NULLIF(BTRIM(status), ''), CASE WHEN administered_by IS NOT NULL THEN 'administered' ELSE 'scheduled' END),
    scheduled_at = COALESCE(scheduled_at, created_at),
    updated_at = COALESCE(updated_at, created_at, now())
WHERE medication_name IS NULL OR BTRIM(medication_name) = ''
   OR status IS NULL OR BTRIM(status) = ''
   OR scheduled_at IS NULL OR updated_at IS NULL;

ALTER TABLE public.medication_administrations
  ALTER COLUMN medication_name SET NOT NULL,
  ALTER COLUMN status SET DEFAULT 'scheduled',
  ALTER COLUMN status SET NOT NULL,
  ALTER COLUMN updated_at SET DEFAULT now(),
  ALTER COLUMN updated_at SET NOT NULL;

CREATE INDEX IF NOT EXISTS idx_mar_patient_time
  ON public.medication_administrations(patient_id, scheduled_at DESC);
CREATE INDEX IF NOT EXISTS idx_mar_status_time
  ON public.medication_administrations(status, scheduled_at);
