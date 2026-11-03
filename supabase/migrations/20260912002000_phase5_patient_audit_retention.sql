-- Preserve patient audit history when a patient record is removed.
-- Support legacy patient_audit_log and canonical patient_audit installations.
-- A missing audit table is not an error on partial legacy installations.
DO $patient_audit_retention$
BEGIN
  IF to_regclass('public.patient_audit_log') IS NOT NULL THEN
    ALTER TABLE public.patient_audit_log ALTER COLUMN patient_id DROP NOT NULL;
    ALTER TABLE public.patient_audit_log DROP CONSTRAINT IF EXISTS patient_audit_log_patient_id_fkey;
    ALTER TABLE public.patient_audit_log
      ADD CONSTRAINT patient_audit_log_patient_id_fkey
      FOREIGN KEY (patient_id) REFERENCES public.patients(id) ON DELETE SET NULL;
    CREATE INDEX IF NOT EXISTS idx_patient_audit_changed_by_time
      ON public.patient_audit_log(changed_by, changed_at DESC);
    DROP POLICY IF EXISTS "admins manage patient audit" ON public.patient_audit_log;
    DROP POLICY IF EXISTS "admins read patient audit" ON public.patient_audit_log;
    CREATE POLICY "admins read patient audit" ON public.patient_audit_log
      FOR SELECT TO authenticated USING (public.has_role(auth.uid(),'admin'));
    REVOKE INSERT, UPDATE, DELETE ON public.patient_audit_log FROM authenticated;
  ELSIF to_regclass('public.patient_audit') IS NOT NULL THEN
    ALTER TABLE public.patient_audit ALTER COLUMN patient_id DROP NOT NULL;
    ALTER TABLE public.patient_audit DROP CONSTRAINT IF EXISTS patient_audit_patient_id_fkey;
    ALTER TABLE public.patient_audit
      ADD CONSTRAINT patient_audit_patient_id_fkey
      FOREIGN KEY (patient_id) REFERENCES public.patients(id) ON DELETE SET NULL;
    CREATE INDEX IF NOT EXISTS idx_patient_audit_actor_time
      ON public.patient_audit(actor_user_id, occurred_at DESC);
    DROP POLICY IF EXISTS "admins manage patient audit" ON public.patient_audit;
    DROP POLICY IF EXISTS "admins read patient audit" ON public.patient_audit;
    CREATE POLICY "admins read patient audit" ON public.patient_audit
      FOR SELECT TO authenticated USING (public.has_role(auth.uid(),'admin'));
    REVOKE INSERT, UPDATE, DELETE ON public.patient_audit FROM authenticated;
  END IF;
END;
$patient_audit_retention$;
