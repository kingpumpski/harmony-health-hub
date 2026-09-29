-- Harden high-impact financial SECURITY DEFINER functions against search_path hijacking.
-- Public schema objects are referenced explicitly; pg_catalog is first for built-ins.

alter function public.transition_insurance_claim_canonical(uuid, text, numeric, numeric, text, text)
  set search_path = pg_catalog, public;

alter function public.update_insurance_claim_financials(uuid, numeric, numeric, text, text)
  set search_path = pg_catalog, public;
