-- Pin security-definer workflow functions to trusted schemas.
ALTER FUNCTION public.link_invoice_item_service_order()
  SET search_path = pg_catalog, public;
REVOKE ALL ON FUNCTION public.link_invoice_item_service_order() FROM PUBLIC, anon, authenticated;

ALTER FUNCTION public.touch_global_hims_updated_at()
  SET search_path = pg_catalog, public;
REVOKE ALL ON FUNCTION public.touch_global_hims_updated_at() FROM PUBLIC, anon, authenticated;

ALTER FUNCTION public.transition_insurance_claim(uuid, text, text)
  SET search_path = pg_catalog, public;

ALTER FUNCTION public.update_insurance_case(uuid, text, text, text, numeric, numeric, text)
  SET search_path = pg_catalog, public;
