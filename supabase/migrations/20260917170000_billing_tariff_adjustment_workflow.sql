-- Governed billing tariff adjustment workflow.
-- Repository migration only: do not apply to production without explicit approval.

-- Keep this migration safe when an environment has the base billing tables but has
-- not yet replayed every historical billing-hardening migration.
ALTER TABLE public.invoice_items
  ADD COLUMN IF NOT EXISTS service_code TEXT,
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS paid_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS paid_by UUID REFERENCES auth.users(id) ON DELETE SET NULL;

CREATE TABLE IF NOT EXISTS public.invoice_item_payments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  invoice_item_id UUID NOT NULL REFERENCES public.invoice_items(id) ON DELETE CASCADE,
  payment_id UUID NOT NULL REFERENCES public.payments(id) ON DELETE CASCADE,
  amount NUMERIC(12,2) NOT NULL CHECK (amount > 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(invoice_item_id, payment_id)
);
ALTER TABLE public.invoice_item_payments ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "invoice item payments staff access" ON public.invoice_item_payments;
CREATE POLICY "invoice item payments staff access" ON public.invoice_item_payments
FOR ALL TO authenticated
USING (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'accountant') OR public.has_role(auth.uid(),'front_desk'))
WITH CHECK (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'accountant') OR public.has_role(auth.uid(),'front_desk'));

CREATE TABLE IF NOT EXISTS public.billing_tariff_adjustments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  invoice_item_id UUID NOT NULL REFERENCES public.invoice_items(id) ON DELETE RESTRICT,
  service_order_id UUID REFERENCES public.service_orders(id) ON DELETE SET NULL,
  service_code TEXT,
  service_name TEXT NOT NULL,
  previous_unit_price NUMERIC(12,2) NOT NULL DEFAULT 0,
  adjusted_unit_price NUMERIC(12,2) NOT NULL CHECK (adjusted_unit_price >= 0),
  quantity INTEGER NOT NULL DEFAULT 1 CHECK (quantity > 0),
  reason TEXT NOT NULL CHECK (length(btrim(reason)) >= 5),
  adjustment_type TEXT NOT NULL DEFAULT 'missing_tariff' CHECK (adjustment_type IN ('missing_tariff','billing_correction')),
  adjusted_by UUID NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  adjusted_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_billing_tariff_adjustments_invoice_item
  ON public.billing_tariff_adjustments(invoice_item_id, adjusted_at DESC);
CREATE INDEX IF NOT EXISTS idx_billing_tariff_adjustments_service_code
  ON public.billing_tariff_adjustments(service_code, adjusted_at DESC);

ALTER TABLE public.billing_tariff_adjustments ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "billing tariff adjustments staff read" ON public.billing_tariff_adjustments;
CREATE POLICY "billing tariff adjustments staff read"
  ON public.billing_tariff_adjustments FOR SELECT TO authenticated
  USING (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'accountant'));

CREATE OR REPLACE FUNCTION public.get_missing_billing_tariffs(_patient_id UUID DEFAULT NULL)
RETURNS TABLE(
  invoice_item_id UUID,
  invoice_id UUID,
  patient_id UUID,
  description TEXT,
  department TEXT,
  service_code TEXT,
  quantity INTEGER,
  unit_price NUMERIC,
  amount NUMERIC,
  service_order_id UUID,
  service_order_status TEXT,
  created_at TIMESTAMPTZ
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public
AS $$
BEGIN
  IF NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'accountant') OR public.has_role(auth.uid(),'front_desk')) THEN
    RAISE EXCEPTION 'Billing access denied';
  END IF;

  RETURN QUERY
  SELECT ii.id, ii.invoice_id, i.patient_id, ii.description, ii.department,
         COALESCE(ii.service_code, so.service_code),
         ii.quantity, ii.unit_price, ii.amount, so.id, so.status, ii.created_at
  FROM public.invoice_items ii
  JOIN public.invoices i ON i.id=ii.invoice_id
  LEFT JOIN LATERAL (
    SELECT s.id,s.status,s.service_code FROM public.service_orders s
    WHERE s.invoice_item_id=ii.id AND s.status<>'cancelled'
    ORDER BY s.created_at DESC LIMIT 1
  ) so ON true
  WHERE ii.amount <= 0
    AND ii.unit_price <= 0
    AND i.status IN ('pending','partially_paid')
    AND (_patient_id IS NULL OR i.patient_id=_patient_id)
  ORDER BY ii.created_at DESC;
END;
$$;

CREATE OR REPLACE FUNCTION public.adjust_invoice_item_tariff(
  _invoice_item_id UUID,
  _adjusted_unit_price NUMERIC,
  _reason TEXT,
  _adjustment_type TEXT DEFAULT 'missing_tariff'
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public
AS $$
DECLARE
  item RECORD;
  order_row RECORD;
  adjustment_id UUID;
  old_price NUMERIC;
  new_amount NUMERIC;
BEGIN
  IF NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'accountant')) THEN
    RAISE EXCEPTION 'Only Accounts or administrators may adjust billing tariffs';
  END IF;
  IF _adjusted_unit_price IS NULL OR _adjusted_unit_price < 0 THEN
    RAISE EXCEPTION 'Adjusted tariff must be zero or greater';
  END IF;
  IF length(btrim(COALESCE(_reason,''))) < 5 THEN
    RAISE EXCEPTION 'A tariff adjustment reason of at least 5 characters is required';
  END IF;
  IF _adjustment_type NOT IN ('missing_tariff','billing_correction') THEN
    RAISE EXCEPTION 'Invalid tariff adjustment type';
  END IF;

  SELECT ii.*, i.status AS invoice_status, i.patient_id
    INTO item
  FROM public.invoice_items ii
  JOIN public.invoices i ON i.id=ii.invoice_id
  WHERE ii.id=_invoice_item_id
  FOR UPDATE OF ii;

  IF item.id IS NULL THEN RAISE EXCEPTION 'Invoice item not found'; END IF;
  IF item.invoice_status NOT IN ('pending','partially_paid') THEN
    RAISE EXCEPTION 'Tariff can only be adjusted on an open or partially paid invoice';
  END IF;
  IF item.paid_at IS NOT NULL OR EXISTS (
    SELECT 1 FROM public.invoice_item_payments ip WHERE ip.invoice_item_id=item.id
  ) THEN
    RAISE EXCEPTION 'Paid invoice items cannot have their tariff changed';
  END IF;

  old_price := COALESCE(item.unit_price,0);
  new_amount := round(_adjusted_unit_price * GREATEST(COALESCE(item.quantity,1),1),2);

  INSERT INTO public.billing_tariff_adjustments(
    invoice_item_id,service_order_id,service_code,service_name,previous_unit_price,
    adjusted_unit_price,quantity,reason,adjustment_type,adjusted_by
  )
  VALUES(
    item.id,NULL,item.service_code,item.description,old_price,_adjusted_unit_price,
    GREATEST(COALESCE(item.quantity,1),1),btrim(_reason),_adjustment_type,auth.uid()
  ) RETURNING id INTO adjustment_id;

  UPDATE public.invoice_items
  SET unit_price=_adjusted_unit_price, amount=new_amount, updated_at=now()
  WHERE id=item.id;

  SELECT s.id,s.status INTO order_row
  FROM public.service_orders s
  WHERE s.invoice_item_id=item.id AND s.status<>'cancelled'
  ORDER BY s.created_at DESC LIMIT 1;

  IF order_row.id IS NOT NULL AND order_row.status='pending_payment_approval' THEN
    UPDATE public.service_orders
    SET amount=new_amount, service_code=COALESCE(service_code,item.service_code)
    WHERE id=order_row.id;
    UPDATE public.billing_tariff_adjustments SET service_order_id=order_row.id WHERE id=adjustment_id;
  END IF;

  UPDATE public.invoices i
  SET total_amount=COALESCE((SELECT SUM(amount) FROM public.invoice_items WHERE invoice_id=i.id),0), updated_at=now()
  WHERE i.id=item.invoice_id;

  PERFORM public.record_system_audit(
    'billing_tariff_adjusted','billing','invoice_item',item.id,'warning',
    jsonb_build_object('patient_id',item.patient_id,'invoice_id',item.invoice_id,'service_code',item.service_code,'previous_unit_price',old_price,'adjusted_unit_price',_adjusted_unit_price,'quantity',GREATEST(COALESCE(item.quantity,1),1),'reason',btrim(_reason),'adjustment_type',_adjustment_type,'adjustment_id',adjustment_id)
  );

  RETURN jsonb_build_object('invoice_item_id',item.id,'invoice_id',item.invoice_id,'adjustment_id',adjustment_id,'unit_price',_adjusted_unit_price,'amount',new_amount,'service_order_id',order_row.id);
END;
$$;

REVOKE ALL ON FUNCTION public.get_missing_billing_tariffs(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.adjust_invoice_item_tariff(UUID,NUMERIC,TEXT,TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_missing_billing_tariffs(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.adjust_invoice_item_tariff(UUID,NUMERIC,TEXT,TEXT) TO authenticated;
