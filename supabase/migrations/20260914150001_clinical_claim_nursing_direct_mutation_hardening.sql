-- Reconcile live clinical mutation boundaries with the repository.
-- Existing lifecycle RPCs are the authoritative mutation path where available.

BEGIN;

REVOKE INSERT, UPDATE, DELETE ON TABLE public.insurance_claims FROM authenticated;
REVOKE INSERT ON TABLE public.nursing_care_plans FROM authenticated;
REVOKE INSERT ON TABLE public.ward_units FROM authenticated;

COMMIT;
