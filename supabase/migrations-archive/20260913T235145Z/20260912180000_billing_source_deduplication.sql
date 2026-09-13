CREATE OR REPLACE FUNCTION public.suppress_duplicate_gated_source_invoice_item()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF NEW.source_type IN ('lab_order','prescription') AND NEW.source_id IS NOT NULL
     AND EXISTS (SELECT 1 FROM public.service_orders so WHERE so.related_entity_id=NEW.source_id AND so.status<>'cancelled' AND COALESCE(so.amount,0)>0) THEN
    RETURN NULL;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_suppress_duplicate_gated_source_invoice_item ON public.invoice_items;
CREATE TRIGGER trg_suppress_duplicate_gated_source_invoice_item BEFORE INSERT ON public.invoice_items FOR EACH ROW EXECUTE FUNCTION public.suppress_duplicate_gated_source_invoice_item();
REVOKE ALL ON FUNCTION public.suppress_duplicate_gated_source_invoice_item() FROM PUBLIC;
