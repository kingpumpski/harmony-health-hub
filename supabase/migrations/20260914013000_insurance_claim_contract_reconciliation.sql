ALTER TABLE public.insurance_claims
  ADD COLUMN IF NOT EXISTS payer_name TEXT,
  ADD COLUMN IF NOT EXISTS member_number TEXT,
  ADD COLUMN IF NOT EXISTS claim_number TEXT,
  ADD COLUMN IF NOT EXISTS amount_paid NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (amount_paid >= 0),
  ADD COLUMN IF NOT EXISTS rejection_reason TEXT,
  ADD COLUMN IF NOT EXISTS service_from TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS service_to TIMESTAMPTZ;

UPDATE public.insurance_claims
SET payer_name = COALESCE(NULLIF(payer_name,''), provider),
    member_number = COALESCE(NULLIF(member_number,''), policy_number),
    amount_paid = COALESCE(amount_paid,0),
    rejection_reason = CASE WHEN status='rejected' THEN COALESCE(rejection_reason, notes) ELSE rejection_reason END
WHERE payer_name IS NULL OR member_number IS NULL OR amount_paid IS NULL OR (status='rejected' AND rejection_reason IS NULL);

ALTER TABLE public.insurance_claims
  ALTER COLUMN payer_name SET NOT NULL;

CREATE INDEX IF NOT EXISTS insurance_claims_invoice_id_idx ON public.insurance_claims(invoice_id);
CREATE INDEX IF NOT EXISTS insurance_claims_patient_id_idx ON public.insurance_claims(patient_id);
CREATE INDEX IF NOT EXISTS insurance_claims_status_idx ON public.insurance_claims(status);

CREATE OR REPLACE FUNCTION public.create_insurance_claim_draft(
  _patient_id UUID,
  _payer_name TEXT,
  _member_number TEXT DEFAULT NULL,
  _amount_claimed NUMERIC DEFAULT 0,
  _invoice_id UUID DEFAULT NULL
)
RETURNS public.insurance_claims
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE v_claim public.insurance_claims; v_invoice UUID := _invoice_id;
BEGIN
  IF auth.uid() IS NULL OR NOT (public.has_role(auth.uid(),'admin'::public.app_role) OR public.has_role(auth.uid(),'accountant'::public.app_role) OR public.has_role(auth.uid(),'front_desk'::public.app_role)) THEN RAISE EXCEPTION 'Insurance claims access required'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.patients WHERE id=_patient_id) THEN RAISE EXCEPTION 'Patient not found'; END IF;
  IF NULLIF(trim(_payer_name),'') IS NULL THEN RAISE EXCEPTION 'Payer name is required'; END IF;
  IF _amount_claimed IS NULL OR _amount_claimed < 0 THEN RAISE EXCEPTION 'Claim amount must be non-negative'; END IF;
  IF v_invoice IS NULL THEN SELECT i.id INTO v_invoice FROM public.invoices i WHERE i.patient_id=_patient_id AND i.status NOT IN ('cancelled') AND i.total_amount > 0 ORDER BY i.created_at DESC LIMIT 1; END IF;
  IF v_invoice IS NULL THEN RAISE EXCEPTION 'An invoice is required before creating an insurance claim'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.invoices WHERE id=v_invoice AND patient_id=_patient_id) THEN RAISE EXCEPTION 'Invoice does not belong to patient'; END IF;
  INSERT INTO public.insurance_claims(invoice_id,patient_id,provider,policy_number,payer_name,member_number,amount_claimed,amount_approved,amount_paid,status,notes,submitted_at)
  VALUES (v_invoice,_patient_id,trim(_payer_name),NULLIF(trim(_member_number),''),trim(_payer_name),NULLIF(trim(_member_number),''),_amount_claimed,NULL,0,'draft',NULL,now()) RETURNING * INTO v_claim;
  RETURN v_claim;
END;
$function$;

CREATE OR REPLACE FUNCTION public.transition_insurance_claim(_claim_id UUID,_to_status TEXT,_notes TEXT DEFAULT NULL)
RETURNS public.insurance_claims
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $function$
DECLARE v public.insurance_claims; v_allowed BOOLEAN := false;
BEGIN
  IF auth.uid() IS NULL OR NOT (public.has_role(auth.uid(),'admin'::public.app_role) OR public.has_role(auth.uid(),'accountant'::public.app_role)) THEN RAISE EXCEPTION 'Insurance claims transition requires accounts or administrator role'; END IF;
  SELECT * INTO v FROM public.insurance_claims WHERE id=_claim_id FOR UPDATE;
  IF v.id IS NULL THEN RAISE EXCEPTION 'Insurance claim not found'; END IF;
  IF _to_status NOT IN ('draft','submitted','acknowledged','under_review','approved','partially_approved','rejected','paid','resubmission_required','voided') THEN RAISE EXCEPTION 'Invalid insurance claim status'; END IF;
  IF v.status = _to_status THEN RETURN v; END IF;
  v_allowed := CASE v.status
    WHEN 'draft' THEN _to_status IN ('submitted','voided')
    WHEN 'submitted' THEN _to_status IN ('acknowledged','under_review','rejected','resubmission_required','voided')
    WHEN 'acknowledged' THEN _to_status IN ('under_review','rejected','resubmission_required','voided')
    WHEN 'under_review' THEN _to_status IN ('approved','partially_approved','rejected','resubmission_required','voided')
    WHEN 'approved' THEN _to_status IN ('paid','resubmission_required','voided')
    WHEN 'partially_approved' THEN _to_status IN ('paid','resubmission_required','voided')
    WHEN 'rejected' THEN _to_status IN ('resubmission_required','voided')
    WHEN 'resubmission_required' THEN _to_status IN ('submitted','voided')
    WHEN 'paid' THEN false WHEN 'voided' THEN false ELSE false END;
  IF NOT v_allowed THEN RAISE EXCEPTION 'Invalid claim transition from % to %', v.status, _to_status; END IF;
  IF _to_status IN ('approved','partially_approved') AND COALESCE(v.amount_approved,0) <= 0 THEN RAISE EXCEPTION 'Approved amount must be recorded before approval'; END IF;
  IF _to_status='paid' AND COALESCE(v.amount_paid,0) <= 0 THEN RAISE EXCEPTION 'Paid amount must be recorded before marking claim paid'; END IF;
  IF _to_status='paid' AND COALESCE(v.amount_paid,0) > COALESCE(v.amount_approved,0) THEN RAISE EXCEPTION 'Paid amount cannot exceed approved amount'; END IF;
  UPDATE public.insurance_claims SET status=_to_status,notes=COALESCE(NULLIF(trim(_notes),''),notes),resolved_at=CASE WHEN _to_status IN ('paid','rejected','voided') THEN COALESCE(resolved_at,now()) ELSE resolved_at END WHERE id=_claim_id RETURNING * INTO v;
  RETURN v;
END;
$function$;

CREATE OR REPLACE FUNCTION public.update_insurance_claim_financials(_claim_id UUID,_amount_approved NUMERIC,_amount_paid NUMERIC,_claim_number TEXT,_rejection_reason TEXT)
RETURNS public.insurance_claims
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $function$
DECLARE v public.insurance_claims;
BEGIN
  IF auth.uid() IS NULL OR NOT (public.has_role(auth.uid(),'admin'::public.app_role) OR public.has_role(auth.uid(),'accountant'::public.app_role)) THEN RAISE EXCEPTION 'Insurance financial updates require accounts or administrator role'; END IF;
  SELECT * INTO v FROM public.insurance_claims WHERE id=_claim_id FOR UPDATE;
  IF v.id IS NULL THEN RAISE EXCEPTION 'Insurance claim not found'; END IF;
  IF v.status IN ('paid','voided') THEN RAISE EXCEPTION 'Financials are locked for terminal claims'; END IF;
  IF _amount_approved IS NOT NULL AND (_amount_approved < 0 OR _amount_approved > v.amount_claimed) THEN RAISE EXCEPTION 'Approved amount must be between zero and claimed amount'; END IF;
  IF _amount_paid IS NOT NULL AND _amount_paid < 0 THEN RAISE EXCEPTION 'Paid amount must be non-negative'; END IF;
  IF _amount_paid IS NOT NULL AND _amount_paid > COALESCE(_amount_approved,v.amount_claimed) THEN RAISE EXCEPTION 'Paid amount cannot exceed approved amount'; END IF;
  UPDATE public.insurance_claims SET amount_approved=_amount_approved,amount_paid=COALESCE(_amount_paid,0),claim_number=NULLIF(trim(_claim_number),''),rejection_reason=NULLIF(trim(_rejection_reason),''),notes=CASE WHEN _rejection_reason IS NOT NULL THEN NULLIF(trim(_rejection_reason),'') ELSE notes END WHERE id=_claim_id RETURNING * INTO v;
  RETURN v;
END;
$function$;

REVOKE ALL ON FUNCTION public.create_insurance_claim_draft(UUID,TEXT,TEXT,NUMERIC,UUID) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.transition_insurance_claim(UUID,TEXT,TEXT) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.update_insurance_claim_financials(UUID,NUMERIC,NUMERIC,TEXT,TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_insurance_claim_draft(UUID,TEXT,TEXT,NUMERIC,UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.transition_insurance_claim(UUID,TEXT,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_insurance_claim_financials(UUID,NUMERIC,NUMERIC,TEXT,TEXT) TO authenticated;
NOTIFY pgrst, 'reload schema';