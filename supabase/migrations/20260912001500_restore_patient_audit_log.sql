-- Restore the append-only patient audit relation before trigger and retention
-- migrations reference it. Preserve legacy rows; only technical IDs are generated.
CREATE TABLE IF NOT EXISTS public.patient_audit_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id uuid REFERENCES public.patients(id) ON DELETE CASCADE,
  changed_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  action text NOT NULL CHECK (action IN ('INSERT','UPDATE','DELETE')),
  changed_at timestamptz NOT NULL DEFAULT now(),
  old_record jsonb,
  new_record jsonb,
  changed_fields text[] NOT NULL DEFAULT '{}'
);

-- Reconcile partially provisioned legacy tables without fabricating audit
-- timestamps, actions, or changed-field history.
ALTER TABLE public.patient_audit_log
  ADD COLUMN IF NOT EXISTS id uuid DEFAULT gen_random_uuid(),
  ADD COLUMN IF NOT EXISTS patient_id uuid,
  ADD COLUMN IF NOT EXISTS changed_by uuid,
  ADD COLUMN IF NOT EXISTS action text,
  ADD COLUMN IF NOT EXISTS changed_at timestamptz,
  ADD COLUMN IF NOT EXISTS old_record jsonb,
  ADD COLUMN IF NOT EXISTS new_record jsonb,
  ADD COLUMN IF NOT EXISTS changed_fields text[];

UPDATE public.patient_audit_log
SET id = gen_random_uuid()
WHERE id IS NULL;

WITH duplicate_ids AS (
  SELECT ctid,
         row_number() OVER (PARTITION BY id ORDER BY changed_at NULLS LAST, ctid) AS duplicate_rank
  FROM public.patient_audit_log
  WHERE id IS NOT NULL
)
UPDATE public.patient_audit_log AS audit
SET id = gen_random_uuid()
FROM duplicate_ids
WHERE audit.ctid = duplicate_ids.ctid
  AND duplicate_ids.duplicate_rank > 1;

DO $patient_audit_reconcile$
BEGIN
  IF EXISTS (SELECT 1 FROM public.patient_audit_log WHERE changed_at IS NULL) THEN
    RAISE EXCEPTION 'Patient audit history contains rows without changed_at; reconcile timestamps from verified source data before proceeding.';
  END IF;
  IF EXISTS (SELECT 1 FROM public.patient_audit_log WHERE changed_fields IS NULL) THEN
    RAISE EXCEPTION 'Patient audit history contains rows without changed_fields; reconcile from verified source data before proceeding.';
  END IF;
  IF EXISTS (SELECT 1 FROM public.patient_audit_log WHERE action IS NULL OR action NOT IN ('INSERT','UPDATE','DELETE')) THEN
    RAISE EXCEPTION 'Patient audit history contains invalid action values; reconcile from verified source data before proceeding.';
  END IF;
END;
$patient_audit_reconcile$;

ALTER TABLE public.patient_audit_log
  ALTER COLUMN id SET DEFAULT gen_random_uuid(),
  ALTER COLUMN id SET NOT NULL,
  ALTER COLUMN changed_at SET DEFAULT now(),
  ALTER COLUMN changed_at SET NOT NULL,
  ALTER COLUMN action SET NOT NULL,
  ALTER COLUMN changed_fields SET DEFAULT '{}',
  ALTER COLUMN changed_fields SET NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS patient_audit_log_id_legacy_uidx
  ON public.patient_audit_log(id);
CREATE INDEX IF NOT EXISTS idx_patient_audit_patient_time
  ON public.patient_audit_log(patient_id, changed_at DESC);
