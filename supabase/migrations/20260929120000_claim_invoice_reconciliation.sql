-- Reconcile insurance claims with canonical insurer and invoice insurance coverage.
CREATE OR REPLACE FUNCTION public.reconcile_insurance_claim_to_invoice(_claim_id uuid)
RETURNS public.insurance_claims
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $function$
DECLARE
  uid uuid := auth.uid();
  c public.insurance_claims;
  v_company uuid;
  v_insurance numeric := 0;
  v_patient uuid;
BEGIN
  IF uid IS NULL OR NOT (public.has_role(uid,'admin') OR public.has_role(uid,'accountant')) THEN
    RAISE EXCEPTION 'Accounts role required';
  END IF;
  SELECT * INTO c FROM public.insurance_claims WHERE id=_claim_id FOR UPDATE;
  IF c.id IS NULL THEN RAISE EXCEPTION 'Claim not found'; END IF;
  IF c.status IN ('paid','voided') THEN RAISE EXCEPTION 'Closed claim cannot be reconciled'; END IF;
  SELECT patient_id INTO v_patient FROM public.invoices WHERE id=c.invoice_id;
  IF v_patient IS DISTINCT FROM c.patient_id THEN RAISE EXCEPTION 'Claim invoice does not belong to claim patient'; END IF;
  SELECT insurance_company_id INTO v_company FROM public.patients WHERE id=c.patient_id;
  IF v_company IS NULL THEN
    SELECT insurance_company_id INTO v_company FROM public.insurance_cases WHERE patient_id=c.patient_id AND eligibility_status='eligible' ORDER BY updated_at DESC LIMIT 1;
  END IF;
  SELECT coalesce(sum(greatest(coalesce(ii.insurance_charge,0),0)),0) INTO v_insurance FROM public.invoice_items ii WHERE ii.invoice_id=c.invoice_id;
  UPDATE public.insurance_claims
  SET insurance_company_id=coalesce(insurance_company_id,v_company),
      amount_approved=least(coalesce(amount_approved,v_insurance),coalesce(c.amount_claimed,0),v_insurance),
      updated_at=now()
  WHERE id=_claim_id RETURNING * INTO c;
  PERFORM public.record_system_audit('insurance_claim_reconciled_to_invoice','insurance','insurance_claim',c.id,'info',jsonb_build_object('invoice_id',c.invoice_id,'insurance_total',v_insurance,'amount_claimed',c.amount_claimed,'amount_approved',c.amount_approved,'actor_id',uid));
  RETURN c;
END;
$function$;
REVOKE ALL ON FUNCTION public.reconcile_insurance_claim_to_invoice(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.reconcile_insurance_claim_to_invoice(uuid) TO authenticated;
