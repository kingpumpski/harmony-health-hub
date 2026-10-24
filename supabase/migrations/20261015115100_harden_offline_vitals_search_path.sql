-- Harden idempotent offline vital-sign replay against search_path shadowing.
ALTER FUNCTION public.record_patient_vitals_offline(
  UUID, UUID, UUID, NUMERIC, INT, INT, INT, INT, INT, NUMERIC, NUMERIC, TEXT, TIMESTAMPTZ
) SET search_path = pg_catalog, public;
