-- Preserve patient audit history when a patient record is removed.
-- The audit row keeps its snapshot while the patient FK becomes nullable.
ALTER TABLE public.patient_audit_log ALTER COLUMN patient_id DROP NOT NULL;
ALTER TABLE public.patient_audit_log DROP CONSTRAINT IF EXISTS patient_audit_log_patient_id_fkey;
ALTER TABLE public.patient_audit_log
  ADD CONSTRAINT patient_audit_log_patient_id_fkey
  FOREIGN KEY (patient_id) REFERENCES public.patients(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_patient_audit_changed_by_time
  ON public.patient_audit_log(changed_by, changed_at DESC);

-- Patient audit records are append-only from the application perspective.
DROP POLICY IF EXISTS "admins manage patient audit" ON public.patient_audit_log;
CREATE POLICY "admins read patient audit" ON public.patient_audit_log
  FOR SELECT TO authenticated
  USING (public.has_role(auth.uid(),'admin'));

REVOKE INSERT, UPDATE, DELETE ON public.patient_audit_log FROM authenticated;
