-- Forward hardening for installations where the earlier audit migrations are already recorded.
-- Preserve both established audit tables; patient_audit_log remains the application-facing log.
DO $patient_audit_hardening$
BEGIN
  IF to_regprocedure('public.audit_patient_change()') IS NOT NULL THEN
    EXECUTE $cmd$ALTER FUNCTION public.audit_patient_change() SET search_path = ''$cmd$;
  END IF;
  IF to_regprocedure('public.audit_patient_changes()') IS NOT NULL THEN
    EXECUTE $cmd$ALTER FUNCTION public.audit_patient_changes() SET search_path = ''$cmd$;
  END IF;
  IF to_regclass('public.patient_audit_log') IS NOT NULL THEN
    EXECUTE 'REVOKE INSERT, UPDATE, DELETE ON public.patient_audit_log FROM authenticated, anon';
  END IF;
END
$patient_audit_hardening$;
