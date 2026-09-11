-- Phase 2: payment-gated service orders and facility routing.
-- This migration extends the existing workflow schema created by
-- 20260911004959_e283cf8c-f6e8-4347-b4c0-689d591d33e4.sql.
-- It intentionally does not recreate facility_settings or service_orders.

ALTER TABLE public.facility_settings
  ADD COLUMN IF NOT EXISTS routing_mode TEXT;

UPDATE public.facility_settings
SET routing_mode = CASE
  WHEN payment_flow = 'strict' THEN 'pay_before_each_step'
  ELSE 'streamlined'
END
WHERE routing_mode IS NULL;

ALTER TABLE public.facility_settings
  ALTER COLUMN routing_mode SET DEFAULT 'pay_before_each_step';

UPDATE public.facility_settings
SET routing_mode = 'pay_before_each_step'
WHERE routing_mode IS NULL;

ALTER TABLE public.facility_settings
  ALTER COLUMN routing_mode SET NOT NULL;

ALTER TABLE public.service_orders
  ADD COLUMN IF NOT EXISTS invoice_item_id UUID REFERENCES public.invoice_items(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS order_type TEXT,
  ADD COLUMN IF NOT EXISTS service_code TEXT,
  ADD COLUMN IF NOT EXISTS quantity NUMERIC(10,2) NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS unit_price NUMERIC(12,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS payment_required BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS released_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS released_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS release_reason TEXT,
  ADD COLUMN IF NOT EXISTS started_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS cancelled_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL;

UPDATE public.service_orders
SET created_by = requested_by
WHERE created_by IS NULL AND requested_by IS NOT NULL;

UPDATE public.service_orders
SET released_at = COALESCE(released_at, approved_at),
    released_by = COALESCE(released_by, approved_by),
    payment_required = CASE WHEN amount > 0 THEN true ELSE false END
WHERE status = 'released';

-- Preserve existing application data while standardising the lifecycle.
UPDATE public.service_orders SET status = 'pending_payment_approval' WHERE status = 'pending_payment';

ALTER TABLE public.service_orders
  ALTER COLUMN status SET DEFAULT 'pending_payment_approval';

ALTER TABLE public.service_orders
  DROP CONSTRAINT IF EXISTS service_orders_status_check;
ALTER TABLE public.service_orders
  ADD CONSTRAINT service_orders_status_check
  CHECK (status IN ('pending_payment_approval','released','in_progress','completed','cancelled'));

ALTER TABLE public.service_orders
  DROP CONSTRAINT IF EXISTS service_orders_quantity_check;
ALTER TABLE public.service_orders
  ADD CONSTRAINT service_orders_quantity_check CHECK (quantity > 0);

ALTER TABLE public.service_orders
  DROP CONSTRAINT IF EXISTS service_orders_unit_price_check;
ALTER TABLE public.service_orders
  ADD CONSTRAINT service_orders_unit_price_check CHECK (unit_price >= 0);

CREATE INDEX IF NOT EXISTS idx_service_orders_department_status
  ON public.service_orders(department, status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_service_orders_invoice
  ON public.service_orders(invoice_id);

CREATE TABLE IF NOT EXISTS public.billing_overrides (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  service_order_id UUID NOT NULL UNIQUE REFERENCES public.service_orders(id) ON DELETE CASCADE,
  reason TEXT NOT NULL CHECK (length(trim(reason)) >= 3),
  approved_by UUID NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  approved_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.department_queues (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  service_order_id UUID NOT NULL UNIQUE REFERENCES public.service_orders(id) ON DELETE CASCADE,
  department TEXT NOT NULL,
  queued_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  claimed_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  claimed_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  status TEXT NOT NULL DEFAULT 'queued' CHECK (status IN ('queued','claimed','completed','cancelled')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_department_queues_work
  ON public.department_queues(department, status, queued_at);

CREATE TABLE IF NOT EXISTS public.service_order_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  service_order_id UUID NOT NULL REFERENCES public.service_orders(id) ON DELETE CASCADE,
  from_status TEXT,
  to_status TEXT NOT NULL,
  actor_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  reason TEXT,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_service_order_events_order_time
  ON public.service_order_events(service_order_id, created_at DESC);

ALTER TABLE public.facility_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.service_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.billing_overrides ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.department_queues ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.service_order_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "staff read facility settings" ON public.facility_settings;
CREATE POLICY "staff read facility settings" ON public.facility_settings FOR SELECT TO authenticated
  USING (public.is_clinical_staff(auth.uid()) OR public.has_role(auth.uid(),'accountant'));

DROP POLICY IF EXISTS "admins manage facility settings" ON public.facility_settings;
DROP POLICY IF EXISTS "Admins manage settings" ON public.facility_settings;
CREATE POLICY "admins manage facility settings" ON public.facility_settings FOR ALL TO authenticated
  USING (public.has_role(auth.uid(),'admin'))
  WITH CHECK (public.has_role(auth.uid(),'admin'));

DROP POLICY IF EXISTS "Staff manage service orders" ON public.service_orders;
DROP POLICY IF EXISTS "staff read service orders" ON public.service_orders;
CREATE POLICY "staff read service orders" ON public.service_orders FOR SELECT TO authenticated
  USING (
    public.has_role(auth.uid(),'admin')
    OR public.has_role(auth.uid(),'accountant')
    OR (
      public.is_clinical_staff(auth.uid())
      AND status <> 'pending_payment_approval'
      AND EXISTS (
        SELECT 1 FROM public.profiles p
        WHERE p.id = auth.uid()
          AND lower(COALESCE(p.department,'')) = lower(service_orders.department)
      )
    )
    OR EXISTS (
      SELECT 1 FROM public.patients p
      WHERE p.id = service_orders.patient_id AND p.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "clinical staff create service orders" ON public.service_orders;
CREATE POLICY "clinical staff create service orders" ON public.service_orders FOR INSERT TO authenticated
  WITH CHECK (
    public.is_clinical_staff(auth.uid())
    AND (created_by = auth.uid() OR requested_by = auth.uid())
    AND status = 'pending_payment_approval'
  );

DROP POLICY IF EXISTS "accounts manage billing overrides" ON public.billing_overrides;
CREATE POLICY "accounts manage billing overrides" ON public.billing_overrides FOR SELECT TO authenticated
  USING (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'accountant'));

DROP POLICY IF EXISTS "staff read department queues" ON public.department_queues;
CREATE POLICY "staff read department queues" ON public.department_queues FOR SELECT TO authenticated
  USING (
    public.has_role(auth.uid(),'admin')
    OR public.has_role(auth.uid(),'accountant')
    OR EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid() AND lower(COALESCE(p.department,'')) = lower(department)
    )
  );

DROP POLICY IF EXISTS "staff manage own department queues" ON public.department_queues;
CREATE POLICY "staff manage own department queues" ON public.department_queues FOR UPDATE TO authenticated
  USING (
    public.has_role(auth.uid(),'admin')
    OR EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid() AND lower(COALESCE(p.department,'')) = lower(department)
    )
  )
  WITH CHECK (
    public.has_role(auth.uid(),'admin')
    OR EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid() AND lower(COALESCE(p.department,'')) = lower(department)
    )
  );

DROP POLICY IF EXISTS "staff read service order events" ON public.service_order_events;
CREATE POLICY "staff read service order events" ON public.service_order_events FOR SELECT TO authenticated
  USING (
    public.has_role(auth.uid(),'admin')
    OR public.has_role(auth.uid(),'accountant')
    OR public.is_clinical_staff(auth.uid())
  );

-- All lifecycle writes are RPC-controlled. Direct service-order status changes
-- are not permitted through the client.
DROP POLICY IF EXISTS "staff update service orders" ON public.service_orders;
DROP POLICY IF EXISTS "staff delete service orders" ON public.service_orders;

CREATE OR REPLACE FUNCTION public.validate_service_order_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
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

CREATE OR REPLACE FUNCTION public.service_order_event_trigger()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO public.service_order_events(service_order_id, from_status, to_status, actor_id, reason)
    VALUES (NEW.id, NULL, NEW.status, COALESCE(NEW.created_by, NEW.requested_by, auth.uid()), 'order_created');
  ELSIF NEW.status IS DISTINCT FROM OLD.status THEN
    INSERT INTO public.service_order_events(service_order_id, from_status, to_status, actor_id, reason)
    VALUES (
      NEW.id,
      OLD.status,
      NEW.status,
      COALESCE(NEW.released_by, NEW.approved_by, auth.uid()),
      NEW.release_reason
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS service_order_event_audit ON public.service_orders;
CREATE TRIGGER service_order_event_audit
AFTER INSERT OR UPDATE OF status ON public.service_orders
FOR EACH ROW EXECUTE FUNCTION public.service_order_event_trigger();

CREATE OR REPLACE FUNCTION public.release_service_order(_service_order_id UUID, _reason TEXT DEFAULT 'Payment received')
RETURNS public.service_orders
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.service_orders;
  v_paid NUMERIC(12,2) := 0;
  v_override BOOLEAN := false;
BEGIN
  IF NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'accountant')) THEN
    RAISE EXCEPTION 'Only Accounts staff can release a service order';
  END IF;

  SELECT * INTO v_order
  FROM public.service_orders
  WHERE id = _service_order_id
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Service order not found'; END IF;
  IF v_order.status <> 'pending_payment_approval' THEN RETURN v_order; END IF;

  SELECT COALESCE(SUM(p.amount),0) INTO v_paid
  FROM public.payments p
  WHERE p.invoice_id = v_order.invoice_id;

  SELECT EXISTS (
    SELECT 1 FROM public.billing_overrides b WHERE b.service_order_id = v_order.id
  ) INTO v_override;

  IF v_order.payment_required
     AND v_order.amount > 0
     AND (v_order.invoice_id IS NULL OR v_paid < v_order.amount)
     AND NOT v_override THEN
    RAISE EXCEPTION 'Payment approval is required before release';
  END IF;

  UPDATE public.service_orders
  SET status = 'released',
      approved_at = now(),
      approved_by = auth.uid(),
      released_at = now(),
      released_by = auth.uid(),
      release_reason = _reason,
      updated_at = now()
  WHERE id = v_order.id
  RETURNING * INTO v_order;

  INSERT INTO public.department_queues(service_order_id, department)
  VALUES (v_order.id, v_order.department)
  ON CONFLICT (service_order_id) DO NOTHING;

  RETURN v_order;
END;
$$;

CREATE OR REPLACE FUNCTION public.grant_service_order_override(_service_order_id UUID, _reason TEXT)
RETURNS public.billing_overrides
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_override public.billing_overrides;
BEGIN
  IF NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'accountant')) THEN
    RAISE EXCEPTION 'Only Accounts staff can grant billing overrides';
  END IF;
  IF length(trim(COALESCE(_reason,''))) < 3 THEN
    RAISE EXCEPTION 'An override reason of at least 3 characters is required';
  END IF;

  INSERT INTO public.billing_overrides(service_order_id, reason, approved_by)
  VALUES (_service_order_id, trim(_reason), auth.uid())
  ON CONFLICT (service_order_id) DO UPDATE
    SET reason = EXCLUDED.reason,
        approved_by = EXCLUDED.approved_by,
        approved_at = now()
  RETURNING * INTO v_override;
  RETURN v_override;
END;
$$;

CREATE OR REPLACE FUNCTION public.cancel_service_order(_service_order_id UUID, _reason TEXT DEFAULT 'Cancelled')
RETURNS public.service_orders
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_order public.service_orders;
BEGIN
  IF NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'accountant') OR public.is_clinical_staff(auth.uid())) THEN
    RAISE EXCEPTION 'Authorised staff required';
  END IF;

  UPDATE public.service_orders
  SET status = 'cancelled',
      notes = trim(COALESCE(_reason, notes, 'Cancelled')),
      cancelled_at = now(),
      release_reason = COALESCE(release_reason, trim(COALESCE(_reason,'Cancelled'))),
      updated_at = now()
  WHERE id = _service_order_id
    AND status IN ('pending_payment_approval','released','in_progress')
  RETURNING * INTO v_order;

  IF NOT FOUND THEN RAISE EXCEPTION 'Order cannot be cancelled in its current state'; END IF;
  UPDATE public.department_queues SET status='cancelled' WHERE service_order_id=v_order.id;
  RETURN v_order;
END;
$$;

CREATE OR REPLACE FUNCTION public.mark_service_order_in_progress(_service_order_id UUID)
RETURNS public.service_orders
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_order public.service_orders;
BEGIN
  IF NOT public.is_clinical_staff(auth.uid()) THEN RAISE EXCEPTION 'Clinical staff required'; END IF;
  UPDATE public.service_orders so
  SET status='in_progress', started_at=COALESCE(started_at,now()), updated_at=now()
  WHERE so.id=_service_order_id
    AND so.status='released'
    AND EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id=auth.uid() AND lower(COALESCE(p.department,''))=lower(so.department)
    )
  RETURNING * INTO v_order;
  IF NOT FOUND THEN RAISE EXCEPTION 'Order must be released and assigned to your department'; END IF;
  UPDATE public.department_queues
  SET status='claimed', claimed_by=auth.uid(), claimed_at=COALESCE(claimed_at,now())
  WHERE service_order_id=_service_order_id;
  RETURN v_order;
END;
$$;

CREATE OR REPLACE FUNCTION public.complete_service_order(_service_order_id UUID)
RETURNS public.service_orders
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_order public.service_orders;
BEGIN
  IF NOT public.is_clinical_staff(auth.uid()) THEN RAISE EXCEPTION 'Clinical staff required'; END IF;
  UPDATE public.service_orders so
  SET status='completed', completed_at=now(), updated_at=now()
  WHERE so.id=_service_order_id
    AND so.status='in_progress'
    AND EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id=auth.uid() AND lower(COALESCE(p.department,''))=lower(so.department)
    )
  RETURNING * INTO v_order;
  IF NOT FOUND THEN RAISE EXCEPTION 'Order must be in progress and assigned to your department'; END IF;
  UPDATE public.department_queues
  SET status='completed', completed_at=now()
  WHERE service_order_id=_service_order_id;
  RETURN v_order;
END;
$$;

CREATE OR REPLACE FUNCTION public.set_facility_routing_mode(_mode TEXT)
RETURNS public.facility_settings
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_settings public.facility_settings;
BEGIN
  IF NOT public.has_role(auth.uid(),'admin') THEN
    RAISE EXCEPTION 'Only administrators can change facility routing';
  END IF;
  IF _mode NOT IN ('pay_before_each_step','streamlined') THEN
    RAISE EXCEPTION 'Invalid routing mode';
  END IF;

  UPDATE public.facility_settings
  SET routing_mode=_mode,
      payment_flow=CASE WHEN _mode='pay_before_each_step' THEN 'strict' ELSE 'streamlined' END,
      updated_at=now()
  WHERE id='default'
  RETURNING * INTO v_settings;
  RETURN v_settings;
END;
$$;

DROP TRIGGER IF EXISTS t_facility_settings_updated ON public.facility_settings;
CREATE TRIGGER t_facility_settings_updated
BEFORE UPDATE ON public.facility_settings
FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

DROP TRIGGER IF EXISTS t_service_orders_updated ON public.service_orders;
CREATE TRIGGER t_service_orders_updated
BEFORE UPDATE ON public.service_orders
FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

REVOKE ALL ON FUNCTION public.release_service_order(UUID,TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.grant_service_order_override(UUID,TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.cancel_service_order(UUID,TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.mark_service_order_in_progress(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.complete_service_order(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.set_facility_routing_mode(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.release_service_order(UUID,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.grant_service_order_override(UUID,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.cancel_service_order(UUID,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_service_order_in_progress(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.complete_service_order(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_facility_routing_mode(TEXT) TO authenticated;
