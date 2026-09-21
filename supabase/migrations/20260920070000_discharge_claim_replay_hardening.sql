-- Harden discharge billing/claim bridge against notification replay and concurrent claim creation.
CREATE OR REPLACE FUNCTION public.create_discharge_insurance_claim(
  _notification_id UUID,
  _payer_name TEXT DEFAULT NULL,
  _member_number TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public
AS $$
DECLARE
  uid UUID := auth.uid();
  v_patient_id UUID;
  v_admission_id UUID;
  v_invoice_id UUID;
  v_amount NUMERIC := 0;
  v_payer TEXT;
  v_claim_id UUID;
  v_existing UUID;
  v_admitted_at TIMESTAMPTZ;
  v_discharged_at TIMESTAMPTZ;
BEGIN
  IF uid IS NULL OR NOT (public.has_role(uid,'admin') OR public.has_role(uid,'accountant')) THEN
    RAISE EXCEPTION 'Accounts role required';
  END IF;

  SELECT n.related_patient_id,n.related_entity_id
    INTO v_patient_id,v_admission_id
  FROM public.notifications n
  WHERE n.id=_notification_id
    AND n.recipient_role='accountant'
    AND n.category='payment'
    AND n.title='Discharged patient ready for billing reconciliation'
  FOR UPDATE;

  IF v_patient_id IS NULL OR v_admission_id IS NULL THEN RAISE EXCEPTION 'Discharge billing handoff not found'; END IF;

  SELECT a.admitted_at,a.discharged_at INTO STRICT
    v_admitted_at,v_discharged_at
  FROM public.admissions a
  WHERE a.id=v_admission_id AND a.patient_id=v_patient_id;

  -- Serialize this handoff by admission so repeated clicks cannot create competing claims.
  PERFORM pg_advisory_xact_lock(hashtextextended(v_admission_id::text,0));

  SELECT r.invoice_id,r.outstanding INTO v_invoice_id,v_amount
  FROM public.reconcile_discharge_billing(_notification_id) r;

  IF v_invoice_id IS NULL THEN RAISE EXCEPTION 'No invoice is available for this discharge'; END IF;

  SELECT COALESCE(NULLIF(trim(_payer_name),''),p.insurance_provider) INTO v_payer
  FROM public.patients p WHERE p.id=v_patient_id;
  IF NULLIF(trim(v_payer),'') IS NULL THEN RAISE EXCEPTION 'Insurance payer is required'; END IF;

  SELECT id INTO v_existing
  FROM public.insurance_claims
  WHERE invoice_id=v_invoice_id AND payer_name=v_payer AND status<>'voided'
  ORDER BY created_at DESC LIMIT 1;

  IF v_existing IS NOT NULL THEN
    RETURN jsonb_build_object('claim_id',v_existing,'invoice_id',v_invoice_id,'status','existing');
  END IF;
  IF v_amount<=0 THEN RAISE EXCEPTION 'No outstanding amount is available to claim'; END IF;

  SELECT public.create_insurance_claim_draft(v_patient_id,v_payer,_member_number,v_amount,v_invoice_id) INTO v_claim_id;

  PERFORM public.record_system_audit('discharge_insurance_claim_created','insurance','insurance_claim',v_claim_id,'info',
    jsonb_build_object('patient_id',v_patient_id,'admission_id',v_admission_id,'invoice_id',v_invoice_id,'amount_claimed',v_amount));

  UPDATE public.notifications SET is_read=true WHERE id=_notification_id AND recipient_role='accountant';

  RETURN jsonb_build_object('claim_id',v_claim_id,'invoice_id',v_invoice_id,'amount_claimed',v_amount,'status','draft');
END;
$$;
REVOKE ALL ON FUNCTION public.create_discharge_insurance_claim(UUID,TEXT,TEXT) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.create_discharge_insurance_claim(UUID,TEXT,TEXT) TO authenticated;
