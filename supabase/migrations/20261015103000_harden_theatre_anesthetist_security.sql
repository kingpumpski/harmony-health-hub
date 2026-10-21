-- Harden the legacy theatre anaesthetist assignment RPC's name resolution.
ALTER FUNCTION public.assign_theatre_anesthetist(uuid, uuid)
  SET search_path = pg_catalog, public;
