-- Harden the clinical change audit trigger against object shadowing.
-- The function writes through the established audit RPC and is trigger-only.
ALTER FUNCTION public.audit_clinical_record_change()
  SET search_path = pg_catalog, public;
REVOKE ALL ON FUNCTION public.audit_clinical_record_change() FROM PUBLIC, anon, authenticated;
