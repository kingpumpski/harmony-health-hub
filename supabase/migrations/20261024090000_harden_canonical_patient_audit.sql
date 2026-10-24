-- Forward repair for deployments where the original phase-8 migration is already recorded.
-- Keep the existing canonical patient_audit table and trigger; do not create a second audit store.
DO $patient_audit_hardening$
BEGIN
  IF to_regprocedure('public.audit_patient_change()') IS NOT NULL THEN
    EXECUTE $cmd$ALTER FUNCTION public.audit_patient_change() SET search_path = ''$cmd$;
  END IF;
  IF to_regclass('public.patient_audit') IS NOT NULL THEN
    EXECUTE 'REVOKE INSERT, UPDATE, DELETE ON public.patient_audit FROM authenticated, anon';
  END IF;
END
$patient_audit_hardening$;
