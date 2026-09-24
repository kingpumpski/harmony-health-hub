-- Harden tariff adjustment -> service-order financial linkage.
-- Branch-only migration; production is unchanged until explicitly deployed.

CREATE OR REPLACE FUNCTION public.adjust_invoice_item_tariff(
  _invoice_item_id uuid,
  _adjusted_unit_price numeric,
  _reason text,
  _adjustment_type text DEFAULT 'missing_tariff'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  item RECORD;
  order_row RECORD;
  adjustment_id UUID;
  old_price NUMERIC;
  new_amount NUMERIC;
  linked_service_order_id UUID;
BEGIN
  IF NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'accountant')) THEN
    RAISE EXCEPTION 'Only Accounts or administrators may adjust billing tariffs';
  END IF;
  IF _adjusted_unit_price IS NULL OR _adjusted_unit_price < 0 THEN
    RAISE EXCEPTION 'Adjusted tariff must be zero or greater';
  END IF;
  IF length(btrim(COALESCE(_reason,''))) < 5 THEN
    RAISE EXCEPTION 'A tariff adjustment reason of at least 5 characters is required';
  END IF;
  IF _adjustment_type NOT IN ('missing_tariff','billing_correction') THEN
    RAISE EXCEPTION 'Invalid tariff adjustment type';
  END IF;

  SELECT
    ii.*,
    i.status AS invoice_status,
    i.patient_id AS invoice_patient_id
  INTO item
  FROM public.invoice_items ii
  JOIN public.invoices i ON i.id=ii.invoice_id
  WHERE ii.id=_invoice_item_id
  FOR UPDATE OF ii;

  IF item.id IS NULL THEN
    RAISE EXCEPTION 'Invoice item not found';
  END IF;

  IF item.invoice_status NOT IN ('pending','partially_paid') THEN
    RAISE EXCEPTION 'Tariff can only be adjusted on an open or partially paid invoice';
  END IF;

  IF item.paid_at IS NOT NULL OR EXISTS (
    SELECT 1 FROM public.invoice_item_payments ip WHERE ip.invoice_item_id=item.id
  ) THEN
    RAISE EXCEPTION 'Paid invoice items cannot have their tariff changed';
  END IF;

  -- The invoice and invoice item must describe the same patient when both
  -- patient columns are populated. This prevents tariff mutation from crossing
  -- patient financial contexts.
  IF item.invoice_patient_id IS NULL THEN
    RAISE EXCEPTION 'Invoice patient context is required for tariff adjustment';
  END IF;
  IF item.patient_id IS NOT NULL AND item.patient_id IS DISTINCT FROM item.invoice_patient_id THEN
    RAISE EXCEPTION 'Invoice item patient does not match invoice patient';
  END IF;

  -- Prefer the canonical invoice_items.service_order_id link. For legacy rows
  -- without that link, retain the historical invoice_item_id lookup, but only
  -- after enforcing the complete patient/invoice/item relationship.
  linked_service_order_id := item.service_order_id;

  IF linked_service_order_id IS NOT NULL THEN
    SELECT s.id,s.patient_id,s.invoice_id,s.invoice_item_id,s.status
      INTO order_row
    FROM public.service_orders s
    WHERE s.id=linked_service_order_id
    FOR UPDATE;

    IF order_row.id IS NULL THEN
      RAISE EXCEPTION 'Linked service order not found';
    END IF;
    IF order_row.patient_id IS DISTINCT FROM item.invoice_patient_id THEN
      RAISE EXCEPTION 'Service order patient does not match invoice patient';
    END IF;
    IF order_row.invoice_id IS DISTINCT FROM item.invoice_id THEN
      RAISE EXCEPTION 'Service order invoice does not match invoice item invoice';
    END IF;
    IF order_row.invoice_item_id IS DISTINCT FROM item.id THEN
      RAISE EXCEPTION 'Service order invoice item does not match invoice item';
    END IF;
  ELSE
    SELECT s.id,s.patient_id,s.invoice_id,s.invoice_item_id,s.status
      INTO order_row
    FROM public.service_orders s
    WHERE s.invoice_item_id=item.id
      AND s.status<>'cancelled'
    ORDER BY s.created_at DESC
    LIMIT 1
    FOR UPDATE;

    IF order_row.id IS NOT NULL THEN
      IF order_row.patient_id IS DISTINCT FROM item.invoice_patient_id THEN
        RAISE EXCEPTION 'Service order patient does not match invoice patient';
      END IF;
      IF order_row.invoice_id IS DISTINCT FROM item.invoice_id THEN
        RAISE EXCEPTION 'Service order invoice does not match invoice item invoice';
      END IF;
      IF order_row.invoice_item_id IS DISTINCT FROM item.id THEN
        RAISE EXCEPTION 'Service order invoice item does not match invoice item';
      END IF;
    END IF;
  END IF;

  old_price := COALESCE(item.unit_price,0);
  new_amount := round(_adjusted_unit_price * GREATEST(COALESCE(item.quantity,1),1),2);

  INSERT INTO public.billing_tariff_adjustments(
    invoice_item_id,service_order_id,service_code,service_name,previous_unit_price,
    adjusted_unit_price,quantity,reason,adjustment_type,adjusted_by
  )
  VALUES(
    item.id,
    order_row.id,
    item.service_code,
    item.description,
    old_price,
    _adjusted_unit_price,
    GREATEST(COALESCE(item.quantity,1),1),
    btrim(_reason),
    _adjustment_type,
    auth.uid()
  )
  RETURNING id INTO adjustment_id;

  UPDATE public.invoice_items
  SET unit_price=_adjusted_unit_price, amount=new_amount, updated_at=now()
  WHERE id=item.id;

  IF order_row.id IS NOT NULL AND order_row.status='pending_payment_approval' THEN
    UPDATE public.service_orders
    SET amount=new_amount, service_code=COALESCE(service_code,item.service_code)
    WHERE id=order_row.id;

    UPDATE public.billing_tariff_adjustments
    SET service_order_id=order_row.id
    WHERE id=adjustment_id;
  END IF;

  UPDATE public.invoices i
  SET total_amount=COALESCE((
    SELECT SUM(amount) FROM public.invoice_items WHERE invoice_id=i.id
  ),0), updated_at=now()
  WHERE i.id=item.invoice_id;

  PERFORM public.record_system_audit(
    'billing_tariff_adjusted',
    'billing',
    'invoice_item',
    item.id,
    'warning',
    jsonb_build_object(
      'patient_id',item.invoice_patient_id,
      'invoice_id',item.invoice_id,
      'service_code',item.service_code,
      'previous_unit_price',old_price,
      'adjusted_unit_price',_adjusted_unit_price,
      'quantity',GREATEST(COALESCE(item.quantity,1),1),
      'reason',btrim(_reason),
      'adjustment_type',_adjustment_type,
      'adjustment_id',adjustment_id,
      'service_order_id',order_row.id
    )
  );

  RETURN jsonb_build_object(
    'invoice_item_id',item.id,
    'invoice_id',item.invoice_id,
    'adjustment_id',adjustment_id,
    'unit_price',_adjusted_unit_price,
    'amount',new_amount,
    'service_order_id',order_row.id
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.adjust_invoice_item_tariff(uuid,numeric,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.adjust_invoice_item_tariff(uuid,numeric,text,text) TO authenticated;
