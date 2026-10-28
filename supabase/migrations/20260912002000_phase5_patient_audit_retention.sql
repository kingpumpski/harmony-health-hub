-- Preserve patient audit history when a patient record is removed.
-- This compatibility table is consumed by later audit migrations and PatientAudit.tsx.
-- The separate public.patient_audit table is created by the Patient Hub migration;
-- do not confuse its columns with this legacy patient_audit_log contract.
CREATE TABLE IF NOT EXISTS public.patient_audit_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id UUID,
  changed_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  action TEXT NOT NULL CHECK (action IN ('INSERT','UPDATE','DELETE')),
  changed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  old_record JSONB,
  new_record JSONB,
  changed_fields TEXT[] NOT NULL DEFAULT '{}'
);

-- Keep the snapshot after the patient row is removed.
ALTER TABLE public.patient_audit_log
  ALTER COLUMN patient_id DROP NOT NULL;

ALTER TABLE public.patient_audit_log
  DROP CONSTRAINT IF EXISTS patient_audit_log_patient_id_fkey;

ALTER TABLE public.patient_audit_log
  ADD CONSTRAINT patient_audit_log_patient_id_fkey
  FOREIGN KEY (patient_id) REFERENCES public.patients(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_patient_audit_changed_by_time
  ON public.patient_audit_log(changed_by, changed_at DESC);

ALTER TABLE public.patient_audit_log ENABLE ROW LEVEL SECURITY;

-- Audit records are append-only for application users; admins may read them.
DROP POLICY IF EXISTS "admins manage patient audit" ON public.patient_audit_log;
DROP POLICY IF EXISTS "admins read patient audit" ON public.patient_audit_log;
CREATE POLICY "admins read patient audit" ON public.patient_audit_log
  FOR SELECT TO authenticated
  USING (public.has_role(auth.uid(),'admin'));

REVOKE INSERT, UPDATE, DELETE ON public.patient_audit_log FROM authenticated;
