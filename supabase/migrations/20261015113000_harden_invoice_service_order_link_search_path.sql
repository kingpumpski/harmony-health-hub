-- Pin the invoice/service-order link trigger to trusted schemas.
ALTER FUNCTION public.link_invoice_item_service_order()
  SET search_path = pg_catalog, public;
REVOKE ALL ON FUNCTION public.link_invoice_item_service_order() FROM PUBLIC, anon, authenticated;
