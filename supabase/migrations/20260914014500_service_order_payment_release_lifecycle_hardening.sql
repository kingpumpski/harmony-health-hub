-- Reconcile invoice payment status and service-order release behavior.
-- This migration is intentionally idempotent and preserves the existing payment model.

CREATE OR REPLACE FUNCTION public.refresh_invoice_totals()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $function$
DECLARE
  inv_id UUID;
  total_paid NUMERIC(10,2);
  inv_total NUMERIC(10,2);
BEGIN
  inv_id := COALESCE(NEW.invoice_id, OLD.invoice_id);
  IF inv_id IS NULL THEN RETURN COALESCE(NEW, OLD); END IF;

  SELECT total_amount INTO inv_total
  FROM public.invoices
  WHERE id = inv_id
  FOR UPDATE;

  IF inv_total IS NULL THEN RETURN COALESCE(NEW, OLD); END IF;

  SELECT COALESCE(SUM(amount),0)
    INTO total_paid
  FROM public.payments
  WHERE invoice_id = inv_id;

  UPDATE public.invoices
  SET paid_amount = total_paid,
      status = CASE
        WHEN total_paid <= 0 THEN 'pending'
        WHEN total_paid < inv_total THEN 'partially_paid'
        ELSE 'paid'
      END,
      updated_at = now()
  WHERE id = inv_id;

  RETURN COALESCE(NEW, OLD);
END;
$function$;

-- There were two equivalent payment triggers. Keep one canonical trigger to
-- prevent duplicate invoice recalculation on every payment mutation.
DROP TRIGGER IF EXISTS payments_refresh_invoice ON public.payments;
DROP TRIGGER IF EXISTS trg_refresh_invoice_totals ON public.payments;
CREATE TRIGGER payments_refresh_invoice
AFTER INSERT OR DELETE OR UPDATE ON public.payments
FOR EACH ROW EXECUTE FUNCTION public.refresh_invoice_totals();

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
AS $function$
DECLARE
  uid uuid := auth.uid();
  pid uuid;
  total numeric := 0;
  payment_id uuid;
  existing_payment public.payments;
  iid uuid;
  due numeric;
  amt numeric;
  normalized_reference text := NULLIF(trim(_reference), '');
BEGIN
  IF uid IS NULL OR NOT (public.has_role(uid,'admin') OR public.has_role(uid,'accountant') OR public.has_role(uid,'front_desk')) THEN
    RAISE EXCEPTION 'Payment collection requires accounts or front-desk role';
  END IF;

  SELECT patient_id INTO pid FROM public.invoices WHERE id = _invoice_id FOR UPDATE;
  IF pid IS NULL THEN RAISE EXCEPTION 'Invoice not found'; END IF;

  IF normalized_reference IS NOT NULL THEN
    SELECT * INTO existing_payment
    FROM public.payments
    WHERE invoice_id = _invoice_id
      AND lower(trim(reference)) = lower(normalized_reference)
    ORDER BY created_at DESC
    LIMIT 1;
    IF existing_payment.id IS NOT NULL THEN
      RETURN jsonb_build_object('payment_id', existing_payment.id,'amount',existing_payment.amount,'invoice_id',_invoice_id,'idempotent_replay',true);
    END IF;
  END IF;

  IF _item_ids IS NULL OR cardinality(_item_ids)=0 THEN RAISE EXCEPTION 'No invoice items selected'; END IF;

  FOR iid IN SELECT unnest(_item_ids) LOOP
    SELECT GREATEST(ii.amount-COALESCE(ii.paid_amount,0),0) INTO due
    FROM public.invoice_items ii
    WHERE ii.id=iid AND ii.invoice_id=_invoice_id
    FOR UPDATE;
    IF due IS NULL THEN RAISE EXCEPTION 'Invoice item does not belong to invoice'; END IF;
    IF due>0 THEN total:=total+due; END IF;
  END LOOP;

  IF total<=0 THEN RAISE EXCEPTION 'Selected items have no outstanding balance'; END IF;

  INSERT INTO public.payments(invoice_id,patient_id,amount,method,reference,received_by,notes)
  VALUES(_invoice_id,pid,total,_method,normalized_reference,uid,'Selected invoice items')
  RETURNING id INTO payment_id;

  FOR iid IN SELECT unnest(_item_ids) LOOP
    SELECT GREATEST(ii.amount-COALESCE(ii.paid_amount,0),0) INTO amt
    FROM public.invoice_items ii
    WHERE ii.id=iid AND ii.invoice_id=_invoice_id
    FOR UPDATE;
    IF amt>0 THEN
      UPDATE public.invoice_items SET paid_amount=COALESCE(paid_amount,0)+amt WHERE id=iid;
      INSERT INTO public.billing_item_payments(invoice_item_id,payment_id,amount) VALUES(iid,payment_id,amt);
      UPDATE public.service_orders
      SET status='released', updated_at=now()
      WHERE invoice_item_id=iid AND status='pending_payment_approval';
    END IF;
  END LOOP;

  UPDATE public.invoices i
  SET paid_amount=COALESCE((SELECT SUM(p.amount) FROM public.payments p WHERE p.invoice_id=i.id),0),
      total_amount=COALESCE((SELECT SUM(ii.amount) FROM public.invoice_items ii WHERE ii.invoice_id=i.id),0),
      status=CASE
        WHEN GREATEST(COALESCE((SELECT SUM(ii.amount-COALESCE(ii.paid_amount,0)) FROM public.invoice_items ii WHERE ii.invoice_id=i.id),0),0)=0 THEN 'paid'
        WHEN COALESCE((SELECT SUM(ii.paid_amount) FROM public.invoice_items ii WHERE ii.invoice_id=i.id),0)>0 THEN 'partially_paid'
        ELSE 'pending'
      END,
      updated_at=now()
  WHERE i.id=_invoice_id;

  RETURN jsonb_build_object('payment_id',payment_id,'amount',total,'invoice_id',_invoice_id,'idempotent_replay',false);
END;
$function$;

REVOKE ALL ON FUNCTION public.refresh_invoice_totals() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.pay_selected_invoice_items(uuid,uuid[],text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.pay_selected_invoice_items(uuid,uuid[],text,text) TO authenticated;

NOTIFY pgrst, 'reload schema';
