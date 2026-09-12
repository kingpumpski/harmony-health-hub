-- Lock sensitive global HIMS operational tables to their server-authoritative RPCs.
-- Reads remain governed by existing RLS policies; client-side lifecycle writes are revoked.

REVOKE INSERT, UPDATE, DELETE ON public.ward_units FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.ward_beds FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.nursing_care_plans FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.nursing_shift_handovers FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.emergency_cases FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.theatre_cases FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.transfusion_records FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.insurance_claims FROM authenticated;

-- Claim events are already append-only through workflow functions.
REVOKE INSERT, UPDATE, DELETE ON public.insurance_claim_events FROM authenticated;

-- Clinical care-plan review remains RPC-only.
REVOKE ALL ON FUNCTION public.create_nursing_care_plan(UUID,TEXT,TEXT,TEXT,TEXT,UUID,UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_nursing_care_plan(UUID,TEXT,TEXT,TEXT,TEXT,UUID,UUID) TO authenticated;
REVOKE ALL ON FUNCTION public.review_nursing_care_plan(UUID,TEXT,TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.review_nursing_care_plan(UUID,TEXT,TEXT) TO authenticated;
