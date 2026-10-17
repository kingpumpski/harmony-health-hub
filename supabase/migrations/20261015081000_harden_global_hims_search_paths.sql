-- Pin trusted name resolution for legacy global HIMS SECURITY DEFINER RPCs.
-- These changes preserve the existing signatures, grants, and application behavior.
ALTER FUNCTION public.create_nursing_shift_handover(uuid, text, text, text, text, boolean, uuid)
  SET search_path = pg_catalog, public;

ALTER FUNCTION public.assign_emergency_officer(uuid, uuid)
  SET search_path = pg_catalog, public;

ALTER FUNCTION public.update_insurance_claim_financials(uuid, numeric, numeric, text, text)
  SET search_path = pg_catalog, public;

ALTER FUNCTION public.record_transfusion_reaction(uuid, boolean, text)
  SET search_path = pg_catalog, public;
