ALTER FUNCTION public.apply_goods_receipt() SECURITY INVOKER;
ALTER FUNCTION public.apply_medication_administration() SECURITY INVOKER;
REVOKE EXECUTE ON FUNCTION public.apply_goods_receipt() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.apply_medication_administration() FROM PUBLIC, anon, authenticated;