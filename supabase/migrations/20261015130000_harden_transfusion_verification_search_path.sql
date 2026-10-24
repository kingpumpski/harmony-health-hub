-- Pin the SECURITY DEFINER transfusion verification RPC to trusted schemas.
-- This is a follow-on hardening migration so existing installations receive the fix.
ALTER FUNCTION public.verify_transfusion_record(UUID, UUID)
  SET search_path = pg_catalog, public;
