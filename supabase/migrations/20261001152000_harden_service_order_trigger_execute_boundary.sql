-- Keep the service-order integrity trigger internal-only.
-- Trigger execution does not require callers to have EXECUTE on the trigger function.
REVOKE EXECUTE ON FUNCTION public.validate_service_order_encounter() FROM PUBLIC, anon, authenticated;

DO $contract$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_trigger
    WHERE tgname = 'service_order_encounter_guard'
      AND tgrelid = 'public.service_orders'::regclass
      AND NOT tgisinternal
  ) THEN
    RAISE EXCEPTION 'Expected service-order facility-lineage trigger is missing';
  END IF;
END;
$contract$;
