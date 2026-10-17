-- Preserve patient audit history when a patient record is removed.
-- Reconcile both the canonical patient_audit schema and the older patient_audit_log
-- schema. CREATE TABLE IF NOT EXISTS does not reconcile names or column contracts.
DO $patient_audit_retention$
DECLARE
  v_constraint RECORD;
BEGIN
  IF to_regclass('public.patient_audit') IS NOT NULL THEN
    ALTER TABLE public.patient_audit ALTER COLUMN patient_id DROP NOT NULL;

    FOR v_constraint IN
      SELECT conname
      FROM pg_constraint
      WHERE conrelid = 'public.patient_audit'::regclass
        AND contype = 'f'
        AND conkey = ARRAY[
          (SELECT attnum FROM pg_attribute
           WHERE attrelid = 'public.patient_audit'::regclass
             AND attname = 'patient_id' AND NOT attisdropped)
        ]::smallint[]
    LOOP
      EXECUTE format('ALTER TABLE public.patient_audit DROP CONSTRAINT %I', v_constraint.conname);
    END LOOP;

    ALTER TABLE public.patient_audit
      ADD CONSTRAINT patient_audit_patient_id_fkey
      FOREIGN KEY (patient_id) REFERENCES public.patients(id) ON DELETE SET NULL;

    CREATE INDEX IF NOT EXISTS idx_patient_audit_actor_time
      ON public.patient_audit(actor_user_id, occurred_at DESC);

    ALTER TABLE public.patient_audit ENABLE ROW LEVEL SECURITY;
    DROP POLICY IF EXISTS "admins manage patient audit" ON public.patient_audit;
    DROP POLICY IF EXISTS "admins read patient audit" ON public.patient_audit;
    CREATE POLICY "admins read patient audit" ON public.patient_audit
      FOR SELECT TO authenticated
      USING (public.has_role(auth.uid(),'admin'));

    REVOKE INSERT, UPDATE, DELETE ON public.patient_audit FROM authenticated;

  ELSIF to_regclass('public.patient_audit_log') IS NOT NULL THEN
    -- Compatibility for deployments that still have the legacy table name.
    ALTER TABLE public.patient_audit_log ALTER COLUMN patient_id DROP NOT NULL;
    ALTER TABLE public.patient_audit_log DROP CONSTRAINT IF EXISTS patient_audit_log_patient_id_fkey;
    ALTER TABLE public.patient_audit_log
      ADD CONSTRAINT patient_audit_log_patient_id_fkey
      FOREIGN KEY (patient_id) REFERENCES public.patients(id) ON DELETE SET NULL;

    CREATE INDEX IF NOT EXISTS idx_patient_audit_changed_by_time
      ON public.patient_audit_log(changed_by, changed_at DESC);

    ALTER TABLE public.patient_audit_log ENABLE ROW LEVEL SECURITY;
    DROP POLICY IF EXISTS "admins manage patient audit" ON public.patient_audit_log;
    DROP POLICY IF EXISTS "admins read patient audit" ON public.patient_audit_log;
    CREATE POLICY "admins read patient audit" ON public.patient_audit_log
      FOR SELECT TO authenticated
      USING (public.has_role(auth.uid(),'admin'));

    REVOKE INSERT, UPDATE, DELETE ON public.patient_audit_log FROM authenticated;
  ELSE
    RAISE EXCEPTION 'Neither public.patient_audit nor public.patient_audit_log exists; refusing to skip patient audit retention hardening';
  END IF;
END;
$patient_audit_retention$;
