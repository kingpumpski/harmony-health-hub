-- Next-generation claims boundary: serialize adjudication and financial mutations,
-- preserve the canonical transition RPC signature, and prevent invalid lifecycle jumps.

CREATE OR REPLACE FUNCTION public.transition_insurance_claim(
  _claim_id UUID, _status TEXT, _amount_approved NUMERIC DEFAULT NULL,
  _amount_paid NUMERIC DEFAULT NULL, _rejection_reason TEXT DEFAULT NULL, _notes TEXT DEFAULT NULL
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE uid UUID := auth.uid(); c public.insurance_claims%ROWTYPE; v_approved NUMERIC; v_paid NUMERIC; v_allowed BOOLEAN := FALSE;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (public.has_role(uid,'admin') OR public.has_role(uid,'accountant')) THEN RAISE EXCEPTION 'Accounts role required'; END IF;
  IF _claim_id IS NULL THEN RAISE EXCEPTION 'Claim is required'; END IF;
  IF _status NOT IN ('submitted','acknowledged','under_review','approved','partially_approved','rejected','paid','resubmission_required','voided') THEN RAISE EXCEPTION 'Invalid claim status'; END IF;

  SELECT * INTO c FROM public.insurance_claims WHERE id=_claim_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Claim not found'; END IF;

  IF c.status IN ('paid','voided') THEN
    IF _status <> c.status THEN RAISE EXCEPTION 'Closed claim cannot change status'; END IF;
    RETURN jsonb_build_object('claim_id',c.id,'status',c.status,'amount_approved',c.amount_approved,'amount_paid',c.amount_paid,'idempotent',TRUE);
  END IF;

  CASE c.status
    WHEN 'submitted' THEN v_allowed := _status IN ('acknowledged','under_review','rejected','resubmission_required','voided');
    WHEN 'acknowledged' THEN v_allowed := _status IN ('under_review','rejected','resubmission_required','voided');
    WHEN 'under_review' THEN v_allowed := _status IN ('approved','partially_approved','rejected','resubmission_required','voided');
    WHEN 'approved' THEN v_allowed := _status IN ('paid','voided');
    WHEN 'partially_approved' THEN v_allowed := _status IN ('paid','voided');
    WHEN 'rejected' THEN v_allowed := _status IN ('resubmission_required','voided');
    WHEN 'resubmission_required' THEN v_allowed := _status IN ('submitted','voided');
    ELSE v_allowed := FALSE;
  END CASE;
  IF NOT v_allowed THEN RAISE EXCEPTION 'Invalid claim transition from % to %',c.status,_status; END IF;

  v_approved := COALESCE(_amount_approved,c.amount_approved);
  v_paid := COALESCE(_amount_paid,c.amount_paid,0);
  IF v_approved IS NOT NULL AND v_approved < 0 THEN RAISE EXCEPTION 'Approved amount cannot be negative'; END IF;
  IF v_paid < 0 THEN RAISE EXCEPTION 'Paid amount cannot be negative'; END IF;
  IF v_approved IS NOT NULL AND v_approved > c.amount_claimed THEN RAISE EXCEPTION 'Approved amount exceeds claimed amount'; END IF;
  IF v_paid > COALESCE(v_approved,c.amount_approved,0) THEN RAISE EXCEPTION 'Paid amount exceeds approved amount'; END IF;
  IF _status IN ('approved','partially_approved') AND v_approved IS NULL THEN RAISE EXCEPTION 'Approved amount is required for an adjudication decision'; END IF;
  IF _status = 'paid' AND v_paid <= 0 THEN RAISE EXCEPTION 'Paid amount is required before marking a claim paid'; END IF;
  IF _status = 'rejected' AND NULLIF(trim(COALESCE(_rejection_reason,'')),'') IS NULL THEN RAISE EXCEPTION 'Rejection reason is required'; END IF;

  UPDATE public.insurance_claims
  SET status=_status,
      amount_approved=CASE WHEN _amount_approved IS NOT NULL THEN _amount_approved ELSE amount_approved END,
      amount_paid=CASE WHEN _status='paid' OR _amount_paid IS NOT NULL THEN v_paid ELSE amount_paid END,
      rejection_reason=CASE WHEN _status='rejected' THEN NULLIF(trim(COALESCE(_rejection_reason,'')),'') ELSE rejection_reason END,
      submitted_at=CASE WHEN _status='submitted' AND submitted_at IS NULL THEN now() ELSE submitted_at END,
      adjudicated_at=CASE WHEN _status IN ('approved','partially_approved','rejected') THEN COALESCE(adjudicated_at,now()) ELSE adjudicated_at END,
      paid_at=CASE WHEN _status='paid' THEN COALESCE(paid_at,now()) ELSE paid_at END,
      updated_at=now()
  WHERE id=c.id;

  INSERT INTO public.insurance_claim_events(claim_id,event_type,from_status,to_status,notes,actor_id)
  VALUES (c.id,'status_changed',c.status,_status,_notes,uid);
  RETURN jsonb_build_object('claim_id',c.id,'status',_status,'amount_approved',COALESCE(_amount_approved,c.amount_approved),'amount_paid',CASE WHEN _status='paid' THEN v_paid ELSE c.amount_paid END);
END; $$;

CREATE OR REPLACE FUNCTION public.update_insurance_claim_financials(
  _claim_id UUID, _amount_approved NUMERIC DEFAULT NULL, _amount_paid NUMERIC DEFAULT NULL,
  _claim_number TEXT DEFAULT NULL, _rejection_reason TEXT DEFAULT NULL
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE uid UUID := auth.uid(); c public.insurance_claims%ROWTYPE; v_approved NUMERIC; v_paid NUMERIC;
BEGIN
  IF uid IS NULL OR NOT (public.has_role(uid,'admin') OR public.has_role(uid,'accountant')) THEN RAISE EXCEPTION 'Accounts role required'; END IF;
  SELECT * INTO c FROM public.insurance_claims WHERE id=_claim_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Claim not found'; END IF;
  IF c.status IN ('paid','voided') THEN RAISE EXCEPTION 'Closed claim cannot be edited'; END IF;

  v_approved := COALESCE(_amount_approved,c.amount_approved);
  v_paid := COALESCE(_amount_paid,c.amount_paid,0);
  IF v_approved IS NOT NULL AND v_approved < 0 THEN RAISE EXCEPTION 'Approved amount cannot be negative'; END IF;
  IF v_approved IS NOT NULL AND v_approved > c.amount_claimed THEN RAISE EXCEPTION 'Approved amount exceeds claimed amount'; END IF;
  IF v_paid < 0 OR v_paid > COALESCE(v_approved,c.amount_approved,0) THEN RAISE EXCEPTION 'Invalid paid amount'; END IF;

  UPDATE public.insurance_claims
  SET amount_approved=CASE WHEN _amount_approved IS NOT NULL THEN _amount_approved ELSE amount_approved END,
      amount_paid=CASE WHEN _amount_paid IS NOT NULL THEN _amount_paid ELSE amount_paid END,
      claim_number=CASE WHEN NULLIF(trim(COALESCE(_claim_number,'')),'') IS NOT NULL THEN NULLIF(trim(_claim_number),'') ELSE claim_number END,
      rejection_reason=CASE WHEN _rejection_reason IS NOT NULL THEN NULLIF(trim(_rejection_reason),'') ELSE rejection_reason END,
      updated_at=now()
  WHERE id=_claim_id;

  INSERT INTO public.insurance_claim_events(claim_id,event_type,from_status,to_status,notes,actor_id)
  VALUES (c.id,'financials_updated',c.status,c.status,concat('approved=',COALESCE(_amount_approved::text,'unchanged'),';paid=',COALESCE(_amount_paid::text,'unchanged')),uid);
  RETURN jsonb_build_object('claim_id',c.id,'amount_approved',v_approved,'amount_paid',v_paid);
END; $$;

REVOKE ALL ON FUNCTION public.transition_insurance_claim(UUID,TEXT,NUMERIC,NUMERIC,TEXT,TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.transition_insurance_claim(UUID,TEXT,NUMERIC,NUMERIC,TEXT,TEXT) TO authenticated;
REVOKE ALL ON FUNCTION public.update_insurance_claim_financials(UUID,NUMERIC,NUMERIC,TEXT,TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_insurance_claim_financials(UUID,NUMERIC,NUMERIC,TEXT,TEXT) TO authenticated;

COMMENT ON FUNCTION public.transition_insurance_claim(UUID,TEXT,NUMERIC,NUMERIC,TEXT,TEXT) IS 'Server-authoritative, row-locked insurance claim lifecycle and adjudication transition. Terminal states are immutable and every mutation records a canonical claim event.';
COMMENT ON FUNCTION public.update_insurance_claim_financials(UUID,NUMERIC,NUMERIC,TEXT,TEXT) IS 'Server-authoritative, row-locked insurance claim financial mutation with amount bounds and canonical claim-event recording.';
