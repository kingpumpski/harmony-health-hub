-- Harden insurance claim financial edits against over-approval and over-payment.
CREATE OR REPLACE FUNCTION public.update_insurance_claim_financials(
  _claim_id UUID,
  _amount_approved NUMERIC DEFAULT NULL,
  _amount_paid NUMERIC DEFAULT NULL,
  _claim_number TEXT DEFAULT NULL,
  _rejection_reason TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public
AS $$
DECLARE
  uid UUID := auth.uid();
  c public.insurance_claims%ROWTYPE;
  v_approved NUMERIC;
  v_paid NUMERIC;
BEGIN
  IF uid IS NULL OR NOT (public.has_role(uid,'admin') OR public.has_role(uid,'accountant')) THEN
    RAISE EXCEPTION 'Accounts role required';
  END IF;

  SELECT * INTO c
  FROM public.insurance_claims
  WHERE id=_claim_id
  FOR UPDATE;

  IF c.id IS NULL THEN RAISE EXCEPTION 'Claim not found'; END IF;
  IF c.status IN ('paid','voided') THEN RAISE EXCEPTION 'Closed claim cannot be edited'; END IF;

  v_approved := COALESCE(_amount_approved,c.amount_approved);
  v_paid := COALESCE(_amount_paid,c.amount_paid);

  IF v_approved IS NOT NULL AND v_approved < 0 THEN
    RAISE EXCEPTION 'Approved amount cannot be negative';
  END IF;
  IF v_paid < 0 THEN
    RAISE EXCEPTION 'Paid amount cannot be negative';
  END IF;
  IF v_approved IS NOT NULL AND v_approved > COALESCE(c.amount_claimed,0) THEN
    RAISE EXCEPTION 'Approved amount cannot exceed claimed amount';
  END IF;
  IF v_paid > COALESCE(v_approved,0) THEN
    RAISE EXCEPTION 'Paid amount cannot exceed approved amount';
  END IF;

  UPDATE public.insurance_claims
  SET amount_approved=COALESCE(_amount_approved,amount_approved),
      amount_paid=COALESCE(_amount_paid,amount_paid),
      claim_number=COALESCE(NULLIF(trim(_claim_number),''),claim_number),
      rejection_reason=COALESCE(_rejection_reason,rejection_reason)
  WHERE id=_claim_id;

  PERFORM public.record_system_audit(
    'insurance_claim_financials_updated','insurance','insurance_claim',_claim_id,'warning',
    jsonb_build_object(
      'patient_id',c.patient_id,
      'invoice_id',c.invoice_id,
      'amount_claimed',c.amount_claimed,
      'amount_approved',v_approved,
      'amount_paid',v_paid,
      'actor_id',uid
    )
  );

  RETURN jsonb_build_object(
    'claim_id',_claim_id,
    'amount_claimed',c.amount_claimed,
    'amount_approved',v_approved,
    'amount_paid',v_paid
  );
END;
$$;

REVOKE ALL ON FUNCTION public.update_insurance_claim_financials(UUID,NUMERIC,NUMERIC,TEXT,TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_insurance_claim_financials(UUID,NUMERIC,NUMERIC,TEXT,TEXT) TO authenticated;
