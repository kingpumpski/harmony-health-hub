-- Phase 8: harden the canonical append-only patient audit path created in Phase 1.
-- Do not introduce a second patient_audit_log store: public.patient_audit is canonical.
ALTER FUNCTION public.audit_patient_change() SET search_path = '';

REVOKE INSERT, UPDATE, DELETE ON public.patient_audit FROM authenticated, anon;
