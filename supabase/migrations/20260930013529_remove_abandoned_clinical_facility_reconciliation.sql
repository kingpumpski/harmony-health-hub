BEGIN;

-- Remove the abandoned isolated-facility reconciliation control plane.
-- This is cleanup only; it does not enable patient-table tenancy isolation.
-- DROP FUNCTION IF EXISTS also removes its grants when the function exists.
-- Do not REVOKE first: the function is not guaranteed to exist in a clean replay,
-- and an unconditional REVOKE fails before the IF EXISTS statement can run.

DROP FUNCTION IF EXISTS public.reconcile_clinical_facility_record(text,uuid,uuid,text);
DROP TABLE IF EXISTS public.clinical_facility_reconciliation;

COMMIT;
