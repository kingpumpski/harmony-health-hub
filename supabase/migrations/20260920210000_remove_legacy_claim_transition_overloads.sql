-- Remove legacy insurance-claim transition overloads after all first-party clients moved to the canonical contract.
-- Canonical contract: transition_insurance_claim_canonical(uuid,text,numeric,numeric,text,text).
REVOKE ALL ON FUNCTION public.transition_insurance_claim(uuid,text,numeric,numeric,text,text,text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.transition_insurance_claim(uuid,text,text) FROM PUBLIC, anon, authenticated;
DROP FUNCTION IF EXISTS public.transition_insurance_claim(uuid,text,numeric,numeric,text,text,text);
DROP FUNCTION IF EXISTS public.transition_insurance_claim(uuid,text,text);
GRANT EXECUTE ON FUNCTION public.transition_insurance_claim_canonical(uuid,text,numeric,numeric,text,text) TO authenticated;