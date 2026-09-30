BEGIN;

-- Remove the abandoned isolated-facility reconciliation control plane.
-- Facility attribution needed by normal clinical workflows is provided by the
-- canonical facility-context migration; this cleanup does not enforce tenancy.

REVOKE ALL ON FUNCTION public.reconcile_clinical_facility_record(text,uuid,uuid,text) FROM PUBLIC, anon, authenticated;
DROP FUNCTION IF EXISTS public.reconcile_clinical_facility_record(text,uuid,uuid,text);
DROP TABLE IF EXISTS public.clinical_facility_reconciliation;

COMMIT;