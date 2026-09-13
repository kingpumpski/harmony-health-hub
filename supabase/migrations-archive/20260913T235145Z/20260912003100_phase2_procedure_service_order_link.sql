-- Correct procedure payment linkage: the service order must be created before the procedure note.
ALTER TABLE public.procedure_notes
  ADD COLUMN IF NOT EXISTS service_order_id UUID REFERENCES public.service_orders(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_procedure_notes_service_order ON public.procedure_notes(service_order_id);

CREATE OR REPLACE FUNCTION public.enforce_service_payment_gate()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_amount NUMERIC := 0;
  v_status TEXT;
BEGIN
  IF TG_TABLE_NAME = 'procedure_notes' THEN
    v_amount := COALESCE(NEW.charge_amount, 0);
    IF COALESCE(v_amount, 0) <= 0 THEN RETURN NEW; END IF;

    IF NEW.service_order_id IS NULL THEN
      RAISE EXCEPTION 'Payment approval required before procedure can proceed';
    END IF;

    SELECT status INTO v_status FROM public.service_orders WHERE id = NEW.service_order_id AND department = 'procedure';
    IF v_status IS NULL OR v_status NOT IN ('released', 'in_progress', 'completed') THEN
      RAISE EXCEPTION 'Payment approval required before procedure can proceed (status: %)', COALESCE(v_status, 'not found');
    END IF;
    RETURN NEW;
  END IF;

  IF TG_TABLE_NAME = 'medication_administrations' THEN
    SELECT COALESCE(pi.unit_price, 0) * COALESCE(NEW.quantity_dispensed, 0)
      INTO v_amount
      FROM public.pharmacy_inventory pi WHERE pi.id = NEW.inventory_id;

    IF COALESCE(v_amount, 0) <= 0 THEN RETURN NEW; END IF;

    SELECT so.status INTO v_status
      FROM public.service_orders so
     WHERE so.related_entity_id = NEW.prescription_id
       AND so.department = 'pharmacy'
       AND so.status <> 'cancelled'
     ORDER BY so.created_at DESC LIMIT 1;

    IF v_status IS NULL OR v_status NOT IN ('released', 'in_progress', 'completed') THEN
      RAISE EXCEPTION 'Payment approval required before pharmacy dispensing can proceed (status: %)', COALESCE(v_status, 'not found');
    END IF;
    RETURN NEW;
  END IF;

  RETURN NEW;
END;
$$;
