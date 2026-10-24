-- Pin the idempotent offline appointment RPC to a trusted search path.
ALTER FUNCTION public.create_patient_appointment_offline(
  UUID, UUID, TIMESTAMPTZ, TEXT, TEXT
) SET search_path = pg_catalog, public;
