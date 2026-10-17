-- Harden prescription lifecycle trigger functions created by legacy migrations.
-- Trigger functions do not need direct client execution grants.
ALTER FUNCTION public.sync_prescription_payment_status()
  SET search_path = pg_catalog, public;
REVOKE ALL ON FUNCTION public.sync_prescription_payment_status() FROM PUBLIC, anon, authenticated;

ALTER FUNCTION public.sync_prescription_dispensing_status()
  SET search_path = pg_catalog, public;
REVOKE ALL ON FUNCTION public.sync_prescription_dispensing_status() FROM PUBLIC, anon, authenticated;
