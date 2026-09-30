BEGIN;

-- Remove the abandoned isolated-facility reconciliation control plane.
-- This is cleanup only; it does not enable patient-table tenancy isolation.

REVOKE ALL ON FUNCTION public.reconcile_clinical_facility_record(text,uuid,uuid,text) FROM PUBLIC, anon, authenticated;
DROP FUNCTION IF EXISTS public.reconcile_clinical_facility_record(text,uuid,uuid,text);
DROP TABLE IF EXISTS public.clinical_facility_reconciliation;

COMMIT;
