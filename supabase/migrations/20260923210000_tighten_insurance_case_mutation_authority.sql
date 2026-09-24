-- Tighten the insurance-case mutation RPC.
-- This RPC can change claim status, claim amounts, approved amounts and rejection
-- reasons. Front-desk staff may perform eligibility/authorization workflows but
-- must not have direct access to financial adjudication through this endpoint.

CREATE OR REPLACE FUNCTION public.update_insurance_case(
  _id UUID,
  _eligibility TEXT,
  _authorization TEXT,
  _claim_status TEXT,
  _claim_amount NUMERIC,
  _approved_amount NUMERIC,
  _rejection_reason TEXT
)
RETURNS public.insurance_cases
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v public.insurance_cases;
BEGIN
  IF auth.uid() IS NULL
     OR NOT (
       public.has_role(auth.uid(),'admin')
       OR public.has_role(auth.uid(),'accountant')
     )
  THEN
    RAISE EXCEPTION 'Accounts or administrator role required';
  END IF;

  IF _eligibility NOT IN ('unknown','eligible','ineligible','pending','expired') THEN
    RAISE EXCEPTION 'Invalid eligibility status';
  END IF;

  IF _claim_status NOT IN ('not_submitted','draft','submitted','under_review','approved','partially_approved','rejected','paid','appealed') THEN
    RAISE EXCEPTION 'Invalid claim status';
  END IF;

  UPDATE public.insurance_cases
  SET eligibility_status=_eligibility,
      eligibility_checked_at=CASE
        WHEN _eligibility<>'unknown' THEN now()
        ELSE eligibility_checked_at
      END,
      authorization_number=_authorization,
      claim_status=_claim_status,
      claim_amount=GREATEST(COALESCE(_claim_amount,0),0),
      approved_amount=GREATEST(COALESCE(_approved_amount,0),0),
      rejection_reason=_rejection_reason,
      checked_by=auth.uid(),
      updated_at=now()
  WHERE id=_id
  RETURNING * INTO v;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Insurance case not found';
  END IF;

  RETURN v;
END;
$$;

REVOKE ALL ON FUNCTION public.update_insurance_case(
  UUID,TEXT,TEXT,TEXT,NUMERIC,NUMERIC,TEXT
) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.update_insurance_case(
  UUID,TEXT,TEXT,TEXT,NUMERIC,NUMERIC,TEXT
) TO authenticated;
