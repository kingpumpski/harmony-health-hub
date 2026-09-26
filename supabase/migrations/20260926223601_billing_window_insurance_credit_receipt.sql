-- Billing window foundation: encounter-aware presentation, insurance tariffs,
-- patient deposits/credits, bill finalization and Ghana Cedi receipt support.

CREATE TABLE IF NOT EXISTS public.insurance_service_tariffs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  payer_name text NOT NULL,
  service_code text NOT NULL,
  service_name text,
  base_charge numeric NOT NULL DEFAULT 0 CHECK (base_charge >= 0),
  insurance_charge numeric NOT NULL DEFAULT 0 CHECK (insurance_charge >= 0),
  top_up numeric NOT NULL DEFAULT 0 CHECK (top_up >= 0),
  effective_from date NOT NULL DEFAULT current_date,
  effective_to date,
  active boolean NOT NULL DEFAULT true,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT insurance_service_tariffs_dates CHECK (effective_to IS NULL OR effective_to >= effective_from),
  CONSTRAINT insurance_service_tariffs_amounts CHECK (insurance_charge + top_up >= 0)
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_insurance_service_tariff_active
  ON public.insurance_service_tariffs (lower(payer_name), service_code, effective_from)
  WHERE active;

CREATE INDEX IF NOT EXISTS idx_insurance_service_tariffs_lookup
  ON public.insurance_service_tariffs (lower(payer_name), service_code, active);

ALTER TABLE public.invoice_items
  ADD COLUMN IF NOT EXISTS insurance_charge numeric NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS top_up numeric NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS billed_at timestamptz,
  ADD COLUMN IF NOT EXISTS billed_by uuid;

CREATE TABLE IF NOT EXISTS public.patient_account_credits (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id uuid NOT NULL REFERENCES public.patients(id) ON DELETE RESTRICT,
  entry_type text NOT NULL CHECK (entry_type IN ('deposit','credit','application','debit')),
  amount numeric NOT NULL CHECK (amount > 0),
  reference text,
  invoice_id uuid REFERENCES public.invoices(id) ON DELETE SET NULL,
  payment_id uuid REFERENCES public.payments(id) ON DELETE SET NULL,
  notes text,
  created_by uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_patient_account_credits_patient
  ON public.patient_account_credits(patient_id, created_at DESC);

ALTER TABLE public.insurance_service_tariffs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.patient_account_credits ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS insurance_service_tariffs_admin_read ON public.insurance_service_tariffs;
CREATE POLICY insurance_service_tariffs_admin_read
  ON public.insurance_service_tariffs FOR SELECT TO authenticated
  USING (
    public.has_role(auth.uid(),'admin')
    OR public.has_role(auth.uid(),'accountant')
  );

DROP POLICY IF EXISTS insurance_service_tariffs_admin_write ON public.insurance_service_tariffs;
CREATE POLICY insurance_service_tariffs_admin_write
  ON public.insurance_service_tariffs FOR ALL TO authenticated
  USING (public.has_role(auth.uid(),'admin'))
  WITH CHECK (public.has_role(auth.uid(),'admin'));

REVOKE ALL ON public.patient_account_credits FROM anon, authenticated;
REVOKE ALL ON public.insurance_service_tariffs FROM anon;
GRANT SELECT ON public.insurance_service_tariffs TO authenticated;

CREATE OR REPLACE FUNCTION public.record_patient_deposit(
  _patient_id uuid,
  _amount numeric,
  _reference text DEFAULT NULL
)
RETURNS public.patient_account_credits
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v public.patient_account_credits;
BEGIN
  IF auth.uid() IS NULL OR NOT (
    public.has_role(auth.uid(),'admin')
    OR public.has_role(auth.uid(),'accountant')
    OR public.has_role(auth.uid(),'front_desk')
  ) THEN
    RAISE EXCEPTION 'Billing access denied';
  END IF;
  IF _amount IS NULL OR _amount <= 0 THEN
    RAISE EXCEPTION 'Deposit amount must be positive';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.patients WHERE id = _patient_id) THEN
    RAISE EXCEPTION 'Patient not found';
  END IF;

  INSERT INTO public.patient_account_credits(
    patient_id, entry_type, amount, reference, created_by
  )
  VALUES (
    _patient_id, 'deposit', round(_amount,2), NULLIF(trim(_reference),''), auth.uid()
  )
  RETURNING * INTO v;
  RETURN v;
END;
$$;

REVOKE ALL ON FUNCTION public.record_patient_deposit(uuid,numeric,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.record_patient_deposit(uuid,numeric,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.mark_billing_items_billed(
  _invoice_id uuid,
  _item_ids uuid[]
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count integer;
BEGIN
  IF auth.uid() IS NULL OR NOT (
    public.has_role(auth.uid(),'admin')
    OR public.has_role(auth.uid(),'accountant')
    OR public.has_role(auth.uid(),'front_desk')
  ) THEN
    RAISE EXCEPTION 'Billing access denied';
  END IF;
  IF _invoice_id IS NULL OR _item_ids IS NULL OR cardinality(_item_ids) = 0 THEN
    RAISE EXCEPTION 'Invoice and billable items are required';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.invoices WHERE id = _invoice_id) THEN
    RAISE EXCEPTION 'Invoice not found';
  END IF;

  UPDATE public.invoice_items
  SET billed_at = COALESCE(billed_at, now()),
      billed_by = COALESCE(billed_by, auth.uid()),
      updated_at = now()
  WHERE invoice_id = _invoice_id
    AND id = ANY(_item_ids);

  GET DIAGNOSTICS v_count = ROW_COUNT;
  IF v_count <> cardinality(_item_ids) THEN
    RAISE EXCEPTION 'One or more billing items do not belong to this invoice';
  END IF;

  RETURN jsonb_build_object('invoice_id',_invoice_id,'billed_items',v_count);
END;
$$;

REVOKE ALL ON FUNCTION public.mark_billing_items_billed(uuid,uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mark_billing_items_billed(uuid,uuid[]) TO authenticated;

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
          GREATEST(COALESCE(ist.insurance_charge,0) * GREATEST(ii.quantity,1),0)
        )
      END,
      top_up = CASE
        WHEN NOT v_insured THEN GREATEST(ii.amount - COALESCE((
          SELECT SUM(ip.amount) FROM public.invoice_item_payments ip WHERE ip.invoice_item_id=ii.id
        ),0),0)
        ELSE GREATEST(
          ii.amount - LEAST(
            ii.amount,
            GREATEST(COALESCE(ist.insurance_charge,0) * GREATEST(ii.quantity,1),0)
          ),
          0
        )
      END,
      updated_at = now()
  FROM LATERAL (
    SELECT t.insurance_charge
    FROM public.insurance_service_tariffs t
    WHERE v_insured
      AND lower(t.payer_name) = lower(v_insurer)
      AND t.service_code = ii.service_code
      AND t.active
      AND t.effective_from <= _at::date
      AND (t.effective_to IS NULL OR t.effective_to >= _at::date)
    ORDER BY t.effective_from DESC
    LIMIT 1
  ) ist
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

  RETURN jsonb_build_object(
    'invoice_id',v_invoice,
    'account_id',i.invoice_number,
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
  )
  FROM public.invoices i
  WHERE i.id = v_invoice;
END;
$$;

REVOKE ALL ON FUNCTION public.get_billing_window(uuid,timestamptz) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_billing_window(uuid,timestamptz) TO authenticated;

NOTIFY pgrst,'reload schema';
