-- Trigger-only security-definer function; it must not be directly callable through the API.
REVOKE EXECUTE ON FUNCTION public.validate_service_order_encounter() FROM PUBLIC, anon, authenticated;
