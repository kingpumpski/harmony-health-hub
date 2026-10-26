-- Ensure the patient audit table exists before the retention migration alters its FK.
-- The later catalogue/audit migration remains responsible for policies and triggers.
CREATE TABLE IF NOT EXISTS public.patient_audit_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id uuid REFERENCES public.patients(id) ON DELETE CASCADE,
  changed_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  action text,
  changed_at timestamptz NOT NULL DEFAULT now(),
  old_record jsonb,
  new_record jsonb,
  changed_fields text[] NOT NULL DEFAULT '{}'
);
ALTER TABLE public.patient_audit_log
  ADD COLUMN IF NOT EXISTS id uuid DEFAULT gen_random_uuid(),
  ADD COLUMN IF NOT EXISTS patient_id uuid,
  ADD COLUMN IF NOT EXISTS changed_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS action text,
  ADD COLUMN IF NOT EXISTS changed_at timestamptz NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS old_record jsonb,
  ADD COLUMN IF NOT EXISTS new_record jsonb,
  ADD COLUMN IF NOT EXISTS changed_fields text[] NOT NULL DEFAULT '{}';
CREATE INDEX IF NOT EXISTS idx_patient_audit_patient_time
  ON public.patient_audit_log(patient_id, changed_at DESC);
