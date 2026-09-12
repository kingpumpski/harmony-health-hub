DO $$
BEGIN
  IF to_regclass('public.service_orders') IS NOT NULL THEN
    UPDATE public.service_orders so
    SET invoice_item_id=ii.id, invoice_id=ii.invoice_id, service_code=COALESCE(so.service_code,ii.service_code)
    FROM public.invoice_items ii
    WHERE ii.source_type='service_order' AND ii.source_id=so.id AND so.invoice_item_id IS NULL;
  END IF;
END;
$$;
