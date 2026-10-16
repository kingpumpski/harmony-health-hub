BEGIN;

-- Repair partially provisioned legacy catalogue tables without rewriting data.
ALTER TABLE public.lab_test_parameters
  ADD COLUMN IF NOT EXISTS sort_order integer NOT NULL DEFAULT 0;

-- Patient-care continuity exposes sensitive clinical domains. Keep trusted
-- schema resolution while retaining its existing role checks and RPC signature.
ALTER FUNCTION public.get_patient_care_continuity(uuid)
  SET search_path = pg_catalog, public;

NOTIFY pgrst, 'reload schema';
COMMIT;
