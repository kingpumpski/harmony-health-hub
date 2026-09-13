CREATE OR REPLACE FUNCTION public.validate_service_order_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.requested_by := COALESCE(NEW.requested_by, auth.uid());
  NEW.created_by := COALESCE(NEW.created_by, auth.uid());
  NEW.status := 'pending_payment_approval';
  NEW.payment_required := COALESCE(NEW.amount,0) > 0;
  NEW.released_at := NULL;
  NEW.released_by := NULL;
  NEW.release_reason := NULL;
  NEW.started_at := NULL;
  NEW.cancelled_at := NULL;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS service_order_insert_guard ON public.service_orders;
CREATE TRIGGER service_order_insert_guard
BEFORE INSERT ON public.service_orders
FOR EACH ROW EXECUTE FUNCTION public.validate_service_order_insert();
