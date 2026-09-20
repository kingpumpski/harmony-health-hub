-- Harden item-level payment collection against concurrent double allocation and invalid methods.
CREATE OR REPLACE FUNCTION public.pay_selected_invoice_items(
  _invoice_id UUID,
  _item_ids UUID[],
  _method TEXT,
  _reference TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public
AS $$
DECLARE
  item RECORD;
  pay_id UUID;
  alloc NUMERIC;
  total NUMERIC := 0;
  order_id UUID;
  uid UUID := auth.uid();
  v_method TEXT := lower(trim(coalesce(_method,'')));
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (public.has_role(uid,'admin') OR public.has_role(uid,'accountant') OR public.has_role(uid,'front_desk')) THEN
    RAISE EXCEPTION 'Billing access denied';
  END IF;
  IF _item_ids IS NULL OR cardinality(_item_ids)=0 THEN RAISE EXCEPTION 'Select at least one unpaid item'; END IF;
  IF v_method NOT IN ('cash','card','mobile_money','momo','bank_transfer','cheque','insurance','other') THEN
    RAISE EXCEPTION 'Invalid payment method';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.invoices WHERE id=_invoice_id) THEN RAISE EXCEPTION 'Invoice not found'; END IF;

  -- Lock the selected invoice items before calculating balances. This makes
  -- concurrent payment requests serialize instead of both seeing the same due amount.
  PERFORM 1
  FROM public.invoice_items
  WHERE invoice_id=_invoice_id AND id=ANY(_item_ids)
  ORDER BY id
  FOR UPDATE;

  IF (SELECT count(*) FROM public.invoice_items WHERE invoice_id=_invoice_id AND id=ANY(_item_ids)) <> cardinality(_item_ids) THEN
    RAISE EXCEPTION 'One or more selected invoice items do not belong to this invoice';
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
  SELECT _invoice_id,patient_id,total,v_method,NULLIF(trim(_reference),''),uid,'Item-level payment'
  FROM public.invoices WHERE id=_invoice_id
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

    SELECT id INTO order_id
    FROM public.service_orders
    WHERE invoice_item_id=item.id AND status<>'cancelled'
    ORDER BY created_at DESC LIMIT 1;

    IF order_id IS NULL AND item.department IS NOT NULL THEN
      INSERT INTO public.service_orders(patient_id,department,service_name,amount,related_entity_id,invoice_id,invoice_item_id,status,requested_by,service_code)
      VALUES((SELECT patient_id FROM public.invoices WHERE id=_invoice_id),item.department,item.description,item.amount,item.source_id,_invoice_id,item.id,'pending_payment_approval',uid,item.service_code)
      RETURNING id INTO order_id;
    END IF;

    IF order_id IS NOT NULL THEN
      PERFORM public.release_service_order(order_id,'Item payment received');
    END IF;
  END LOOP;

  RETURN jsonb_build_object('invoice_id',_invoice_id,'payment_id',pay_id,'amount',total);
END;
$$;

REVOKE ALL ON FUNCTION public.pay_selected_invoice_items(UUID,UUID[],TEXT,TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.pay_selected_invoice_items(UUID,UUID[],TEXT,TEXT) TO authenticated;
