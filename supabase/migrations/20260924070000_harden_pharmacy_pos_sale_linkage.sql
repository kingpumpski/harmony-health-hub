-- Prevent pharmacy POS confirmation from completing against a service order
-- belonging to a different patient or sale.
CREATE OR REPLACE FUNCTION public.confirm_pharmacy_pos_sale(_sale_id uuid)
RETURNS public.pharmacy_pos_sales
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  result public.pharmacy_pos_sales;
  item public.pharmacy_inventory;
  order_row public.service_orders%ROWTYPE;
  uid uuid := auth.uid();
BEGIN
  IF uid IS NULL OR NOT (
    public.has_role(uid,'admin')
    OR public.has_role(uid,'pharmacist')
  ) THEN
    RAISE EXCEPTION 'Pharmacist role required';
  END IF;

  SELECT * INTO result
  FROM public.pharmacy_pos_sales
  WHERE id=_sale_id
  FOR UPDATE;

  IF NOT FOUND OR result.status <> 'awaiting_payment' THEN
    RAISE EXCEPTION 'POS sale is not awaiting payment';
  END IF;

  IF result.patient_id IS NULL THEN
    RAISE EXCEPTION 'POS sale has no patient';
  END IF;

  SELECT * INTO order_row
  FROM public.service_orders
  WHERE id=result.service_order_id
  FOR UPDATE;

  IF NOT FOUND
     OR order_row.patient_id IS DISTINCT FROM result.patient_id
     OR order_row.related_entity_id IS DISTINCT FROM result.id
     OR order_row.order_type IS DISTINCT FROM 'drug'
     OR order_row.status NOT IN ('released','in_progress') THEN
    RAISE EXCEPTION 'POS sale service order does not match sale';
  END IF;

  SELECT * INTO item
  FROM public.pharmacy_inventory
  WHERE id=result.inventory_id
  FOR UPDATE;

  IF NOT FOUND OR NOT item.active OR item.stock_quantity < result.quantity THEN
    RAISE EXCEPTION 'Insufficient or unavailable stock at dispensing time';
  END IF;

  UPDATE public.pharmacy_inventory
  SET stock_quantity=stock_quantity-result.quantity,
      updated_at=now()
  WHERE id=item.id;

  UPDATE public.pharmacy_pos_sales
  SET status='dispensed',
      dispensed_by=uid,
      dispensed_at=now()
  WHERE id=result.id
    AND status='awaiting_payment'
  RETURNING * INTO result;

  IF result.id IS NULL THEN
    RAISE EXCEPTION 'POS sale could not be confirmed';
  END IF;

  UPDATE public.service_orders
  SET status='completed',
      completed_at=COALESCE(completed_at,now()),
      updated_at=now()
  WHERE id=order_row.id
    AND status IN ('released','in_progress');

  RETURN result;
END;
$$;

REVOKE ALL ON FUNCTION public.confirm_pharmacy_pos_sale(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.confirm_pharmacy_pos_sale(uuid) TO authenticated;
