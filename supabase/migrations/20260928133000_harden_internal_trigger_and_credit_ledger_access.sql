-- Security advisor reconciliation: remove direct API execution from an internal trigger
-- function and make the intentionally non-addressable credit ledger explicitly deny
-- direct authenticated table access. Privileged billing RPCs remain the supported API.

DO $ward_guard$
BEGIN
  -- Some supported schema histories do not install this optional trigger
  -- helper. Revoke execution only when the exact zero-argument signature exists.
  IF to_regprocedure('public.set_ward_facility_context()') IS NOT NULL THEN
    EXECUTE 'REVOKE ALL ON FUNCTION public.set_ward_facility_context() FROM PUBLIC, anon, authenticated';
  END IF;
END;
$ward_guard$;

DROP POLICY IF EXISTS patient_account_credits_no_direct_access
  ON public.patient_account_credits;

CREATE POLICY patient_account_credits_no_direct_access
  ON public.patient_account_credits
  FOR ALL
  TO authenticated
  USING (false)
  WITH CHECK (false);

REVOKE ALL ON public.patient_account_credits FROM anon, authenticated;
