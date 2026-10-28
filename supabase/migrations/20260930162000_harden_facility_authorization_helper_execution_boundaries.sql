-- Harden facility authorization helper functions against direct Data API execution.
--
-- These helpers are used by server-side/RLS authorization paths and are not
-- application RPC entry points. Keep their privileged execution available to
-- database policy evaluation while denying direct client execution.

ALTER FUNCTION public.has_facility_access(uuid, uuid)
  SET search_path = '';
REVOKE EXECUTE ON FUNCTION public.has_facility_access(uuid, uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.has_facility_access(uuid, uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.has_facility_access(uuid, uuid) FROM authenticated;

ALTER FUNCTION public.current_user_has_facility_access(uuid)
  SET search_path = '';
REVOKE EXECUTE ON FUNCTION public.current_user_has_facility_access(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.current_user_has_facility_access(uuid) FROM anon;
-- RLS policies call this authenticated-session wrapper. Keep the low-level
-- two-argument helper internal-only, but preserve EXECUTE for authenticated
-- policy evaluation through the one-argument wrapper.
GRANT EXECUTE ON FUNCTION public.current_user_has_facility_access(uuid) TO authenticated;
