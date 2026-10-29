-- Harden insurance claim lifecycle transitions with explicit state and financial prerequisites.
CREATE OR REPLACE FUNCTION public.transition_insurance_claim_canonical(
  _claim_id UUID,
  _status TEXT,
  _amount_approved NUMERIC DEFAULT NULL,
  _amount_paid NUMERIC DEFAULT NULL,
  _rejection_reason TEXT DEFAULT NULL,
  _notes TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  c public.insurance_claims%ROWTYPE;
  uid UUID := auth.uid();
  v_approved NUMERIC;
  v_paid NUMERIC;
  v_from TEXT;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (public.has_role(uid,'admin') OR public.has_role(uid,'accountant')) THEN
    RAISE EXCEPTION 'Accounts role required';
  END IF;
  IF _status NOT IN ('submitted','acknowledged','under_review','approved','partially_approved','rejected','paid','resubmission_required','voided') THEN
    RAISE EXCEPTION 'Invalid claim status';
  END IF;

  SELECT * INTO c FROM public.insurance_claims WHERE id=_claim_id FOR UPDATE;
  IF c.id IS NULL THEN RAISE EXCEPTION 'Claim not found'; END IF;
  v_from := c.status;

  IF v_from IN ('paid','voided') THEN
    RAISE EXCEPTION 'Closed claim cannot change status';
  END IF;

  IF _status='submitted' AND v_from NOT IN ('draft','resubmission_required') THEN
    RAISE EXCEPTION 'Claim can only be submitted from draft or resubmission required';
  END IF;
  IF _status='acknowledged' AND v_from <> 'submitted' THEN
    RAISE EXCEPTION 'Claim must be submitted before acknowledgement';
  END IF;
  IF _status='under_review' AND v_from <> 'acknowledged' THEN
    RAISE EXCEPTION 'Claim must be acknowledged before review';
  END IF;
  IF _status IN ('approved','partially_approved','rejected','resubmission_required') AND v_from <> 'under_review' THEN
    RAISE EXCEPTION 'Claim must be under review before adjudication';
  END IF;
  IF _status='paid' AND v_from NOT IN ('approved','partially_approved') THEN
    RAISE EXCEPTION 'Only approved claims can be marked paid';
  END IF;

  v_approved := COALESCE(_amount_approved,c.amount_approved);
  v_paid := COALESCE(_amount_paid,c.amount_paid);

  IF v_approved IS NOT NULL AND v_approved < 0 THEN RAISE EXCEPTION 'Approved amount cannot be negative'; END IF;
  IF v_paid < 0 THEN RAISE EXCEPTION 'Paid amount cannot be negative'; END IF;
  IF v_approved IS NOT NULL AND v_approved > COALESCE(c.amount_claimed,0) THEN
    RAISE EXCEPTION 'Approved amount exceeds claimed amount';
  END IF;
  IF v_paid > COALESCE(v_approved,0) THEN
    RAISE EXCEPTION 'Paid amount exceeds approved amount';
  END IF;
  IF _status IN ('approved','partially_approved') AND v_approved IS NULL THEN
    RAISE EXCEPTION 'Approved amount is required for adjudication';
  END IF;
  IF _status='paid' AND COALESCE(v_paid,0) <= 0 THEN
    RAISE EXCEPTION 'Paid amount is required before marking claim paid';
  END IF;
  IF _status='rejected' AND NULLIF(trim(COALESCE(_rejection_reason,'')),'') IS NULL THEN
    RAISE EXCEPTION 'Rejection reason is required';
  END IF;

  UPDATE public.insurance_claims
  SET status=_status,
      amount_approved=COALESCE(_amount_approved,amount_approved),
      amount_paid=COALESCE(_amount_paid,amount_paid),
      rejection_reason=CASE WHEN _status='rejected' THEN COALESCE(NULLIF(trim(_rejection_reason),''),rejection_reason) ELSE rejection_reason END,
      submitted_at=CASE WHEN _status='submitted' AND submitted_at IS NULL THEN now() ELSE submitted_at END,
      adjudicated_at=CASE WHEN _status IN ('approved','partially_approved','rejected') THEN COALESCE(adjudicated_at,now()) ELSE adjudicated_at END,
      paid_at=CASE WHEN _status='paid' THEN COALESCE(paid_at,now()) ELSE paid_at END,
      updated_at=now()
  WHERE id=_claim_id;

  INSERT INTO public.insurance_claim_events(claim_id,event_type,from_status,to_status,notes,actor_id)
  VALUES (_claim_id,'status_changed',v_from,_status,_notes,uid);

  RETURN jsonb_build_object('claim_id',_claim_id,'status',_status,'amount_approved',v_approved,'amount_paid',v_paid);
END; $$;

REVOKE ALL ON FUNCTION public.transition_insurance_claim_canonical(UUID,TEXT,NUMERIC,NUMERIC,TEXT,TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.transition_insurance_claim_canonical(UUID,TEXT,NUMERIC,NUMERIC,TEXT,TEXT) TO authenticated;
