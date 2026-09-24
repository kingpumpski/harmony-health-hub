CREATE OR REPLACE FUNCTION public.pay_selected_invoice_items(
  _invoice_id uuid,
  _item_ids uuid[],
  _method text,
  _reference text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  item RECORD;
  inv_patient uuid;
  pay_id uuid;
  alloc numeric;
  total numeric := 0;
  order_row public.service_orders;
  uid uuid := auth.uid();
  v_method text := lower(trim(coalesce(_method,'')));
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (public.has_role(uid,'admin') OR public.has_role(uid,'accountant') OR public.has_role(uid,'front_desk')) THEN
    RAISE EXCEPTION 'Billing access denied';
  END IF;
  IF _item_ids IS NULL OR cardinality(_item_ids)=0 THEN RAISE EXCEPTION 'Select at least one unpaid item'; END IF;
  IF v_method NOT IN ('cash','card','mobile_money','momo','bank_transfer','cheque','insurance','other') THEN
    RAISE EXCEPTION 'Invalid payment method';
  END IF;

  SELECT patient_id INTO inv_patient
  FROM public.invoices
  WHERE id=_invoice_id AND status IN ('pending','partially_paid')
  FOR UPDATE;
  IF NOT FOUND OR inv_patient IS NULL THEN
    RAISE EXCEPTION 'Invoice must be open and linked to a patient';
  END IF;

  PERFORM 1
  FROM public.invoice_items
  WHERE invoice_id=_invoice_id AND id=ANY(_item_ids)
  ORDER BY id
  FOR UPDATE;

  IF (SELECT count(*) FROM public.invoice_items WHERE invoice_id=_invoice_id AND id=ANY(_item_ids)) <> cardinality(_item_ids) THEN
    RAISE EXCEPTION 'One or more selected invoice items do not belong to this invoice';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.invoice_items
    WHERE invoice_id=_invoice_id AND id=ANY(_item_ids)
      AND (patient_id IS NOT NULL AND patient_id IS DISTINCT FROM inv_patient)
  ) THEN
    RAISE EXCEPTION 'Invoice item does not belong to invoice patient';
  END IF;

  FOR item IN
    SELECT ii.*, GREATEST(ii.amount-COALESCE((SELECT SUM(ip.amount) FROM public.invoice_item_payments ip WHERE ip.invoice_item_id=ii.id),0),0) AS due
    FROM public.invoice_items ii
    WHERE ii.invoice_id=_invoice_id AND ii.id=ANY(_item_ids)
    ORDER BY ii.id
  LOOP
    IF item.due > 0 THEN total := total + item.due; END IF;
  END LOOP;
  IF total <= 0 THEN RAISE EXCEPTION 'Selected items are already paid'; END IF;

  INSERT INTO public.payments(invoice_id,patient_id,amount,method,reference,received_by,notes)
  VALUES(_invoice_id,inv_patient,total,v_method,NULLIF(trim(_reference),''),uid,'Item-level payment')
  RETURNING id INTO pay_id;

  FOR item IN
    SELECT ii.*, GREATEST(ii.amount-COALESCE((SELECT SUM(ip.amount) FROM public.invoice_item_payments ip WHERE ip.invoice_item_id=ii.id),0),0) AS due
    FROM public.invoice_items ii
    WHERE ii.invoice_id=_invoice_id AND ii.id=ANY(_item_ids)
    ORDER BY ii.id
  LOOP
    IF item.due <= 0 THEN CONTINUE; END IF;
    alloc := item.due;
    INSERT INTO public.invoice_item_payments(invoice_item_id,payment_id,amount)
    VALUES(item.id,pay_id,alloc);
    UPDATE public.invoice_items SET paid_at=now(),paid_by=uid WHERE id=item.id;

    SELECT s.* INTO order_row
    FROM public.service_orders s
    WHERE s.invoice_item_id=item.id AND s.status<>'cancelled'
    ORDER BY s.created_at DESC LIMIT 1
    FOR UPDATE;

    IF order_row.id IS NOT NULL THEN
      IF order_row.patient_id IS DISTINCT FROM inv_patient
         OR order_row.invoice_id IS DISTINCT FROM _invoice_id THEN
        RAISE EXCEPTION 'Service order does not match invoice patient or invoice';
      END IF;
      IF order_row.invoice_item_id IS DISTINCT FROM item.id THEN
        RAISE EXCEPTION 'Service order does not match invoice item';
      END IF;
    ELSIF item.department IS NOT NULL THEN
      INSERT INTO public.service_orders(patient_id,department,service_name,amount,related_entity_id,invoice_id,invoice_item_id,status,requested_by,service_code)
      VALUES(inv_patient,item.department,item.description,item.amount,item.source_id,_invoice_id,item.id,'pending_payment_approval',uid,item.service_code)
      RETURNING * INTO order_row;
      UPDATE public.invoice_items SET service_order_id=order_row.id WHERE id=item.id AND service_order_id IS NULL;
    END IF;

    IF order_row.id IS NOT NULL THEN
      PERFORM public.release_service_order(order_row.id,'Item payment received');
    END IF;
  END LOOP;

  UPDATE public.invoices
  SET total_amount=COALESCE((SELECT SUM(amount) FROM public.invoice_items WHERE invoice_id=_invoice_id),0),
      status=CASE
        WHEN COALESCE((SELECT SUM(ii.amount-COALESCE((SELECT SUM(ip.amount) FROM public.invoice_item_payments ip WHERE ip.invoice_item_id=ii.id),0)) FROM public.invoice_items ii WHERE ii.invoice_id=_invoice_id),0) <= 0
        THEN 'paid'
        ELSE 'partially_paid'
      END,
      updated_at=now()
  WHERE id=_invoice_id;

  RETURN jsonb_build_object('invoice_id',_invoice_id,'payment_id',pay_id,'amount',total);
END;
$$;

REVOKE ALL ON FUNCTION public.pay_selected_invoice_items(uuid,uuid[],text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pay_selected_invoice_items(uuid,uuid[],text,text) TO authenticated;
