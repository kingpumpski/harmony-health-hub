CREATE OR REPLACE FUNCTION public.link_invoice_item_service_order()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF NEW.source_type='service_order' AND NEW.source_id IS NOT NULL THEN
    UPDATE public.service_orders SET invoice_item_id=NEW.id, invoice_id=NEW.invoice_id WHERE id=NEW.source_id AND invoice_item_id IS NULL;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_link_invoice_item_service_order ON public.invoice_items;
CREATE TRIGGER trg_link_invoice_item_service_order AFTER INSERT ON public.invoice_items FOR EACH ROW EXECUTE FUNCTION public.link_invoice_item_service_order();
REVOKE ALL ON FUNCTION public.link_invoice_item_service_order() FROM PUBLIC;
