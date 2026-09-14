-- Prevent duplicate collection when the same external payment reference is retried.
-- References remain optional for payment methods that do not provide one.
CREATE UNIQUE INDEX IF NOT EXISTS payments_invoice_reference_uidx
  ON public.payments (invoice_id, lower(trim(reference)))
  WHERE NULLIF(trim(reference), '') IS NOT NULL;

CREATE OR REPLACE FUNCTION public.pay_selected_invoice_items(
  _invoice_id UUID,
  _item_ids UUID[],
  _method TEXT,
  _reference TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  uid UUID := auth.uid();
  pid UUID;
  total NUMERIC := 0;
  payment_id UUID;
  existing_payment public.payments;
  iid UUID;
  due NUMERIC;
  amt NUMERIC;
  normalized_reference TEXT := NULLIF(trim(_reference), '');
BEGIN
  IF uid IS NULL OR NOT (
    public.has_role(uid,'admin') OR
    public.has_role(uid,'accountant') OR
    public.has_role(uid,'front_desk')
  ) THEN
    RAISE EXCEPTION 'Payment collection requires accounts or front-desk role';
  END IF;

  SELECT patient_id INTO pid
  FROM public.invoices
  WHERE id = _invoice_id
  FOR UPDATE;
  IF pid IS NULL THEN RAISE EXCEPTION 'Invoice not found'; END IF;

  -- Treat a repeated non-empty payment reference as an idempotent replay.
  -- This protects retries/double-clicks without making reference mandatory.
  IF normalized_reference IS NOT NULL THEN
    SELECT * INTO existing_payment
    FROM public.payments
    WHERE invoice_id = _invoice_id
      AND lower(trim(reference)) = lower(normalized_reference)
    ORDER BY created_at DESC
    LIMIT 1;

    IF existing_payment.id IS NOT NULL THEN
      RETURN jsonb_build_object(
        'payment_id', existing_payment.id,
        'amount', existing_payment.amount,
        'invoice_id', _invoice_id,
        'idempotent_replay', true
      );
    END IF;
  END IF;

  IF _item_ids IS NULL OR cardinality(_item_ids)=0 THEN
    RAISE EXCEPTION 'No invoice items selected';
  END IF;

  FOR iid IN SELECT unnest(_item_ids) LOOP
    SELECT GREATEST(ii.amount-COALESCE(ii.paid_amount,0),0)
      INTO due
    FROM public.invoice_items ii
    WHERE ii.id=iid AND ii.invoice_id=_invoice_id
    FOR UPDATE;
    IF due IS NULL THEN RAISE EXCEPTION 'Invoice item does not belong to invoice'; END IF;
    IF due>0 THEN total:=total+due; END IF;
  END LOOP;

  IF total<=0 THEN RAISE EXCEPTION 'Selected items have no outstanding balance'; END IF;

  INSERT INTO public.payments(
    invoice_id, patient_id, amount, method, reference, received_by, notes
  )
  VALUES(
    _invoice_id, pid, total, _method, normalized_reference, uid, 'Selected invoice items'
  )
  RETURNING id INTO payment_id;

  FOR iid IN SELECT unnest(_item_ids) LOOP
    SELECT GREATEST(ii.amount-COALESCE(ii.paid_amount,0),0)
      INTO amt
    FROM public.invoice_items ii
    WHERE ii.id=iid AND ii.invoice_id=_invoice_id
    FOR UPDATE;

    IF amt>0 THEN
      UPDATE public.invoice_items
      SET paid_amount=COALESCE(paid_amount,0)+amt
      WHERE id=iid;

      INSERT INTO public.billing_item_payments(invoice_item_id,payment_id,amount)
      VALUES(iid,payment_id,amt);

      UPDATE public.service_orders
      SET status='released', updated_at=now()
      WHERE invoice_item_id=iid AND status='pending_payment_approval';
    END IF;
  END LOOP;

  UPDATE public.invoices i
  SET paid_amount=COALESCE((SELECT SUM(p.amount) FROM public.payments p WHERE p.invoice_id=i.id),0),
      total_amount=COALESCE((SELECT SUM(ii.amount) FROM public.invoice_items ii WHERE ii.invoice_id=i.id),0),
      status=CASE
        WHEN GREATEST(COALESCE((SELECT SUM(ii.amount-COALESCE(ii.paid_amount,0)) FROM public.invoice_items ii WHERE ii.invoice_id=i.id),0),0)=0
          THEN 'paid'
        ELSE 'partial'
      END,
      updated_at=now()
  WHERE i.id=_invoice_id;

  RETURN jsonb_build_object(
    'payment_id',payment_id,
    'amount',total,
    'invoice_id',_invoice_id,
    'idempotent_replay',false
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.pay_selected_invoice_items(UUID,UUID[],TEXT,TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pay_selected_invoice_items(UUID,UUID[],TEXT,TEXT) TO authenticated;
NOTIFY pgrst, 'reload schema';
