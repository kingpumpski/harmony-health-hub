-- Server-authoritative discharge -> Accounts reconciliation.
-- Reuses the existing bill preparation path; it does not create a second billing ledger.

CREATE OR REPLACE FUNCTION public.reconcile_discharge_billing(_notification_id UUID)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  uid UUID := auth.uid();
  v_patient_id UUID;
  v_admission_id UUID;
  v_admitted_at TIMESTAMPTZ;
  v_discharged_at TIMESTAMPTZ;
  v_invoice_id UUID;
  v_gross NUMERIC := 0;
  v_paid NUMERIC := 0;
  v_outstanding NUMERIC := 0;
  v_claimed NUMERIC := 0;
  v_claim_paid NUMERIC := 0;
  r RECORD;
BEGIN
  IF uid IS NULL OR NOT (public.has_role(uid,'admin') OR public.has_role(uid,'accountant')) THEN
    RAISE EXCEPTION 'Accounts role required';
  END IF;

  SELECT n.related_patient_id, n.related_entity_id
    INTO v_patient_id, v_admission_id
  FROM public.notifications n
  WHERE n.id = _notification_id
    AND n.recipient_role = 'accountant'
    AND n.category = 'payment'
    AND n.title = 'Discharged patient ready for billing reconciliation';

  IF v_patient_id IS NULL THEN
    RAISE EXCEPTION 'Discharge billing handoff not found';
  END IF;

  SELECT a.admitted_at, a.discharged_at
    INTO v_admitted_at, v_discharged_at
  FROM public.admissions a
  WHERE a.id = v_admission_id AND a.patient_id = v_patient_id;

  IF v_admitted_at IS NULL THEN
    RAISE EXCEPTION 'Discharge admission record not found';
  END IF;

  FOR r IN
    SELECT * FROM public.prepare_patient_billable_items(
      v_patient_id,
      v_admitted_at,
      COALESCE(v_discharged_at, now())
    )
  LOOP
    v_invoice_id := COALESCE(v_invoice_id, r.invoice_id);
    v_gross := v_gross + COALESCE(r.amount, 0);
    v_paid := v_paid + COALESCE(r.paid_amount, 0);
    v_outstanding := v_outstanding + COALESCE(r.outstanding_amount, 0);
  END LOOP;

  IF v_invoice_id IS NOT NULL THEN
    SELECT COALESCE(SUM(amount_claimed),0), COALESCE(SUM(amount_paid),0)
      INTO v_claimed, v_claim_paid
    FROM public.insurance_claims
    WHERE invoice_id = v_invoice_id
      AND status <> 'voided';
  END IF;

  UPDATE public.notifications
  SET is_read = true
  WHERE id = _notification_id
    AND recipient_role = 'accountant';

  PERFORM public.record_system_audit(
    'discharge_billing_reconciled',
    'billing',
    'admission',
    v_admission_id,
    'info',
    jsonb_build_object(
      'patient_id', v_patient_id,
      'invoice_id', v_invoice_id,
      'gross', v_gross,
      'paid', v_paid,
      'outstanding', v_outstanding,
      'insurance_claimed', v_claimed,
      'insurance_paid', v_claim_paid
    )
  );

  RETURN jsonb_build_object(
    'notification_id', _notification_id,
    'admission_id', v_admission_id,
    'patient_id', v_patient_id,
    'invoice_id', v_invoice_id,
    'gross', v_gross,
    'paid', v_paid,
    'outstanding', v_outstanding,
    'insurance_claimed', v_claimed,
    'insurance_paid', v_claim_paid,
    'status', CASE
      WHEN v_outstanding <= 0 THEN 'fully_settled'
      WHEN v_claimed > 0 AND v_claim_paid >= v_claimed THEN 'patient_balance_due'
      WHEN v_claimed > 0 THEN 'insurance_pending'
      ELSE 'patient_balance_due'
    END
  );
END;
$$;

REVOKE ALL ON FUNCTION public.reconcile_discharge_billing(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.reconcile_discharge_billing(UUID) TO authenticated;
