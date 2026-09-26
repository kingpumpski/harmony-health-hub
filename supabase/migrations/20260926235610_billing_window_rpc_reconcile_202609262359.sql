-- Reconcile the production billing-window RPC into repository migration history.
-- This is intentionally idempotent and preserves the canonical argument order.
CREATE OR REPLACE FUNCTION public.get_billing_window(
  _patient_id uuid,
  _at timestamptz DEFAULT now()
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_patient public.patients;
  v_encounter uuid;
  v_invoice uuid;
  v_start timestamptz := date_trunc('day', COALESCE(_at,now()));
  v_end timestamptz := date_trunc('day', COALESCE(_at,now())) + interval '1 day' - interval '1 microsecond';
  v_insured boolean := false;
  v_insurer text;
  v_credit numeric := 0;
  v_total numeric := 0;
  v_insurance numeric := 0;
  v_topup numeric := 0;
  v_items jsonb;
  v_account_id text;
BEGIN
  IF auth.uid() IS NULL OR NOT (
    public.has_role(auth.uid(),'admin')
    OR public.has_role(auth.uid(),'accountant')
    OR public.has_role(auth.uid(),'front_desk')
  ) THEN
    RAISE EXCEPTION 'Billing access denied';
  END IF;

  SELECT * INTO v_patient FROM public.patients WHERE id = _patient_id AND COALESCE(status,'active') <> 'inactive';
  IF v_patient.id IS NULL THEN RAISE EXCEPTION 'Active patient not found'; END IF;

  SELECT e.id INTO v_encounter
  FROM public.encounters e
  WHERE e.patient_id = _patient_id
    AND e.created_at <= v_end
    AND (e.completed_at IS NULL OR e.completed_at >= v_start)
  ORDER BY COALESCE(e.started_at,e.created_at) DESC
  LIMIT 1;

  v_insured :=
    NULLIF(trim(v_patient.insurance_provider),'') IS NOT NULL
    AND NULLIF(trim(v_patient.insurance_number),'') IS NOT NULL
    AND (v_patient.insurance_expiry IS NULL OR v_patient.insurance_expiry >= _at::date);

  IF v_insured THEN
    SELECT c.payer_name INTO v_insurer
    FROM public.insurance_cases c
    WHERE c.patient_id = _patient_id
      AND c.eligibility_status = 'eligible'
      AND c.created_at <= v_end
    ORDER BY c.updated_at DESC
    LIMIT 1;
    v_insurer := COALESCE(v_insurer,v_patient.insurance_provider);
  END IF;

  PERFORM public.prepare_patient_billable_items(_patient_id,v_start,v_end);

  SELECT i.id INTO v_invoice
  FROM public.invoices i
  WHERE i.patient_id = _patient_id
    AND i.status IN ('pending','partially_paid')
  ORDER BY i.created_at DESC
  LIMIT 1
  FOR UPDATE;

  IF v_invoice IS NULL THEN
    RAISE EXCEPTION 'Billing invoice could not be prepared';
  END IF;

  IF v_encounter IS NOT NULL THEN
    UPDATE public.invoices
    SET encounter_id = COALESCE(encounter_id,v_encounter), updated_at = now()
    WHERE id = v_invoice;
  END IF;

  UPDATE public.invoice_items ii
  SET insurance_charge = CASE
        WHEN NOT v_insured THEN 0
        ELSE LEAST(
          ii.amount,
          GREATEST(COALESCE((
            SELECT t.insurance_charge
            FROM public.insurance_service_tariffs t
            WHERE lower(t.payer_name) = lower(v_insurer)
              AND t.service_code = ii.service_code
              AND t.active
              AND t.effective_from <= _at::date
              AND (t.effective_to IS NULL OR t.effective_to >= _at::date)
            ORDER BY t.effective_from DESC
            LIMIT 1
          ),0) * GREATEST(ii.quantity,1),0)
        )
      END,
      top_up = CASE
        WHEN NOT v_insured THEN GREATEST(ii.amount - COALESCE((
          SELECT SUM(ip.amount) FROM public.invoice_item_payments ip WHERE ip.invoice_item_id=ii.id
        ),0),0)
        ELSE GREATEST(
          ii.amount - LEAST(
            ii.amount,
            GREATEST(COALESCE((
              SELECT t.insurance_charge
              FROM public.insurance_service_tariffs t
              WHERE lower(t.payer_name) = lower(v_insurer)
                AND t.service_code = ii.service_code
                AND t.active
                AND t.effective_from <= _at::date
                AND (t.effective_to IS NULL OR t.effective_to >= _at::date)
              ORDER BY t.effective_from DESC
              LIMIT 1
            ),0) * GREATEST(ii.quantity,1),0)
          ),
          0
        )
      END,
      updated_at = now()
  WHERE ii.invoice_id = v_invoice;

  SELECT
    COALESCE(SUM(ii.amount),0),
    COALESCE(SUM(ii.insurance_charge),0),
    COALESCE(SUM(CASE WHEN v_insured THEN ii.top_up ELSE ii.amount END),0)
  INTO v_total,v_insurance,v_topup
  FROM public.invoice_items ii
  WHERE ii.invoice_id = v_invoice;

  SELECT COALESCE(SUM(
    CASE WHEN entry_type IN ('deposit','credit') THEN amount ELSE -amount END
  ),0)
  INTO v_credit
  FROM public.patient_account_credits
  WHERE patient_id = _patient_id;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'invoice_item_id',ii.id,
    'source_type',ii.source_type,
    'source_id',ii.source_id,
    'description',ii.description,
    'category',ii.category,
    'department',ii.department,
    'quantity',ii.quantity,
    'unit_price',ii.unit_price,
    'charge',ii.amount,
    'insurance_charge',COALESCE(ii.insurance_charge,0),
    'top_up',CASE WHEN v_insured THEN COALESCE(ii.top_up,ii.amount) ELSE ii.amount END,
    'paid_amount',COALESCE((SELECT SUM(ip.amount) FROM public.invoice_item_payments ip WHERE ip.invoice_item_id=ii.id),0),
    'outstanding_amount',GREATEST(ii.amount-COALESCE((SELECT SUM(ip.amount) FROM public.invoice_item_payments ip WHERE ip.invoice_item_id=ii.id),0),0),
    'billed_at',ii.billed_at,
    'service_order_id',so.id,
    'service_order_status',so.status
  ) ORDER BY ii.created_at),'[]'::jsonb)
  INTO v_items
  FROM public.invoice_items ii
  LEFT JOIN LATERAL (
    SELECT s.id,s.status
    FROM public.service_orders s
    WHERE s.invoice_item_id = ii.id
    ORDER BY s.created_at DESC
    LIMIT 1
  ) so ON true
  WHERE ii.invoice_id = v_invoice;

  SELECT i.invoice_number INTO v_account_id
  FROM public.invoices i
  WHERE i.id = v_invoice;

  RETURN jsonb_build_object(
    'invoice_id',v_invoice,
    'account_id',v_account_id,
    'records_folder_id',v_patient.patient_code,
    'patient_name',concat_ws(' ',v_patient.first_name,v_patient.last_name),
    'patient_type',CASE WHEN v_insured THEN 'Insured' ELSE 'Cash / Non-Insured' END,
    'insurance_name',CASE WHEN v_insured THEN v_insurer ELSE NULL END,
    'encounter_id',v_encounter,
    'date_time',COALESCE(_at,now()),
    'total_amount',round(v_total,2),
    'insurance_total',round(v_insurance,2),
    'top_up_total',round(v_topup,2),
    'credit_balance',round(v_credit,2),
    'amount_due',round(v_topup-v_credit,2),
    'items',v_items
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_billing_window(uuid,timestamptz) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_billing_window(uuid,timestamptz) TO authenticated;

NOTIFY pgrst,'reload schema';
