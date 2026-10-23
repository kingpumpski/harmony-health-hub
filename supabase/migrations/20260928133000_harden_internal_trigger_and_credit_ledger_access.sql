-- Security advisor reconciliation: make the intentionally non-addressable credit ledger
-- explicitly deny direct authenticated table access. Privileged billing RPCs remain the supported API.

DROP POLICY IF EXISTS patient_account_credits_no_direct_access
  ON public.patient_account_credits;

CREATE POLICY patient_account_credits_no_direct_access
  ON public.patient_account_credits
  FOR ALL
  TO authenticated
  USING (false)
  WITH CHECK (false);

REVOKE ALL ON public.patient_account_credits FROM anon, authenticated;
