-- SECURITY DEFINER functions must not inherit an attacker-controlled
-- search_path. Keep the existing operational workspace behavior while making
-- name resolution deterministic.
BEGIN;

ALTER FUNCTION public.get_operational_workspace(text, integer)
  SET search_path = pg_catalog, public;

COMMIT;