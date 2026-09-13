-- Reconcile prescription state with the payment-gated pharmacy workflow.
-- A prescription remains clinically distinct from its pharmacy service order:
-- unpaid/pending -> paid after the linked billable item is fully paid ->
-- dispensed after the pharmacy dispensing plan is completed.

CREATE OR REPLACE FUNCTION public.sync_prescription_payment_status()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  prescription_uuid UUID;
  item_amount NUMERIC;
  paid_amount NUMERIC;
BEGIN
  SELECT so.related_entity_id
    INTO prescription_uuid
  FROM public.service_orders so
  WHERE so.invoice_item_id = NEW.invoice_item_id
    AND so.department = 'pharmacy'
    AND so.related_entity_id IS NOT NULL
  ORDER BY so.created_at DESC
  LIMIT 1;

  IF prescription_uuid IS NULL THEN
    SELECT ii.source_id
      INTO prescription_uuid
    FROM public.invoice_items ii
    WHERE ii.id = NEW.invoice_item_id
      AND ii.source_type = 'prescription';
  END IF;

  IF prescription_uuid IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT ii.amount
    INTO item_amount
  FROM public.invoice_items ii
  WHERE ii.id = NEW.invoice_item_id;

  SELECT COALESCE(SUM(ip.amount), 0)
    INTO paid_amount
  FROM public.invoice_item_payments ip
  WHERE ip.invoice_item_id = NEW.invoice_item_id;

  IF item_amount IS NOT NULL AND paid_amount >= item_amount THEN
    UPDATE public.prescriptions
    SET status = 'paid', updated_at = now()
    WHERE id = prescription_uuid
      AND status NOT IN ('cancelled', 'dispensed');
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_prescription_payment_status
ON public.invoice_item_payments;

CREATE TRIGGER trg_sync_prescription_payment_status
AFTER INSERT OR UPDATE OF amount ON public.invoice_item_payments
FOR EACH ROW
EXECUTE FUNCTION public.sync_prescription_payment_status();

CREATE OR REPLACE FUNCTION public.sync_prescription_dispensing_status()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.status = 'dispensed' AND NEW.prescription_id IS NOT NULL THEN
    UPDATE public.prescriptions
    SET status = 'dispensed', updated_at = now()
    WHERE id = NEW.prescription_id
      AND status <> 'cancelled';
  ELSIF NEW.status = 'cancelled' AND NEW.prescription_id IS NOT NULL THEN
    UPDATE public.prescriptions
    SET status = 'cancelled', updated_at = now()
    WHERE id = NEW.prescription_id
      AND status NOT IN ('dispensed');
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_prescription_dispensing_status
ON public.pharmacy_dispensing_plans;

CREATE TRIGGER trg_sync_prescription_dispensing_status
AFTER INSERT OR UPDATE OF status ON public.pharmacy_dispensing_plans
FOR EACH ROW
EXECUTE FUNCTION public.sync_prescription_dispensing_status();

REVOKE ALL ON FUNCTION public.sync_prescription_payment_status() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.sync_prescription_dispensing_status() FROM PUBLIC;

-- Reconcile already-paid pharmacy invoice lines where the original payment
-- predates this lifecycle trigger.
UPDATE public.prescriptions p
SET status = 'paid', updated_at = now()
FROM public.service_orders so
JOIN public.invoice_items ii ON ii.id = so.invoice_item_id
WHERE so.department = 'pharmacy'
  AND so.related_entity_id = p.id
  AND so.invoice_item_id IS NOT NULL
  AND p.status NOT IN ('cancelled', 'dispensed')
  AND ii.amount <= COALESCE((
    SELECT SUM(ip.amount)
    FROM public.invoice_item_payments ip
    WHERE ip.invoice_item_id = ii.id
  ), 0);
