-- Preserve patient audit history when a patient record is removed.
-- The audit row keeps its snapshot while the patient FK becomes nullable.
-- The canonical audit table created by the preceding migration is patient_audit
-- (actor_user_id / occurred_at), not the stale patient_audit_log schema.
ALTER TABLE public.patient_audit
  ALTER COLUMN patient_id DROP NOT NULL;

ALTER TABLE public.patient_audit
  DROP CONSTRAINT IF EXISTS patient_audit_patient_id_fkey;

ALTER TABLE public.patient_audit
  ADD CONSTRAINT patient_audit_patient_id_fkey
  FOREIGN KEY (patient_id) REFERENCES public.patients(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_patient_audit_actor_time
  ON public.patient_audit(actor_user_id, occurred_at DESC);

-- Patient audit records are append-only from the application perspective.
DROP POLICY IF EXISTS "admins manage patient audit" ON public.patient_audit;
DROP POLICY IF EXISTS "admins read patient audit" ON public.patient_audit;
CREATE POLICY "admins read patient audit" ON public.patient_audit
  FOR SELECT TO authenticated
  USING (public.has_role(auth.uid(),'admin'));

REVOKE INSERT, UPDATE, DELETE ON public.patient_audit FROM authenticated;
