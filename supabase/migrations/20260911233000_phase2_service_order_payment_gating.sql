-- Phase 2: payment-gated service orders and facility routing.
-- Database-enforced lifecycle: pending_payment_approval -> released -> in_progress -> completed/cancelled.

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'service_order_status') THEN
    CREATE TYPE public.service_order_status AS ENUM (
      'pending_payment_approval', 'released', 'in_progress', 'completed', 'cancelled'
    );
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'facility_routing_mode') THEN
    CREATE TYPE public.facility_routing_mode AS ENUM (
      'pay_before_each_step', 'streamlined'
    );
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.facility_settings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  facility_name TEXT NOT NULL DEFAULT 'Harmony Health Hub',
  routing_mode public.facility_routing_mode NOT NULL DEFAULT 'pay_before_each_step',
  currency TEXT NOT NULL DEFAULT 'GHS',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_facility_settings_singleton ON public.facility_settings ((true));
INSERT INTO public.facility_settings (facility_name)
SELECT 'Harmony Health Hub'
WHERE NOT EXISTS (SELECT 1 FROM public.facility_settings);

CREATE TABLE IF NOT EXISTS public.service_orders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id UUID NOT NULL REFERENCES public.patients(id) ON DELETE CASCADE,
  encounter_id UUID REFERENCES public.encounters(id) ON DELETE SET NULL,
  invoice_id UUID REFERENCES public.invoices(id) ON DELETE SET NULL,
  invoice_item_id UUID REFERENCES public.invoice_items(id) ON DELETE SET NULL,
  order_type TEXT NOT NULL CHECK (order_type IN ('lab','imaging','procedure','drug')),
  service_code TEXT,
  service_name TEXT NOT NULL,
  department TEXT NOT NULL,
  quantity NUMERIC(10,2) NOT NULL DEFAULT 1 CHECK (quantity > 0),
  unit_price NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (unit_price >= 0),
  amount NUMERIC(12,2) GENERATED ALWAYS AS (quantity * unit_price) STORED,
  status public.service_order_status NOT NULL DEFAULT 'pending_payment_approval',
  payment_required BOOLEAN NOT NULL DEFAULT true,
  released_at TIMESTAMPTZ,
  released_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  release_reason TEXT,
  started_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  cancelled_at TIMESTAMPTZ,
  created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_service_orders_patient_time ON public.service_orders(patient_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_service_orders_department_status ON public.service_orders(department, status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_service_orders_invoice ON public.service_orders(invoice_id);

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

CREATE INDEX IF NOT EXISTS idx_department_queues_work ON public.department_queues(department, status, queued_at);

CREATE TABLE IF NOT EXISTS public.service_order_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  service_order_id UUID NOT NULL REFERENCES public.service_orders(id) ON DELETE CASCADE,
  from_status public.service_order_status,
  to_status public.service_order_status NOT NULL,
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
CREATE POLICY "staff read facility settings" ON public.facility_settings FOR SELECT
  USING (public.is_clinical_staff(auth.uid()) OR public.has_role(auth.uid(),'accountant'));
DROP POLICY IF EXISTS "admins manage facility settings" ON public.facility_settings;
CREATE POLICY "admins manage facility settings" ON public.facility_settings FOR ALL
  USING (public.has_role(auth.uid(),'admin')) WITH CHECK (public.has_role(auth.uid(),'admin'));

DROP POLICY IF EXISTS "staff read service orders" ON public.service_orders;
CREATE POLICY "staff read service orders" ON public.service_orders FOR SELECT
  USING (
    public.has_role(auth.uid(),'admin')
    OR public.has_role(auth.uid(),'accountant')
    OR (
      public.is_clinical_staff(auth.uid())
      AND status <> 'pending_payment_approval'
      AND (
        department IS NULL
        OR EXISTS (
          SELECT 1 FROM public.profiles p
          WHERE p.id = auth.uid() AND (p.department IS NULL OR lower(p.department) = lower(service_orders.department))
        )
      )
    )
    OR EXISTS (
      SELECT 1 FROM public.patients p WHERE p.id = patient_id AND p.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "clinical staff create service orders" ON public.service_orders;
CREATE POLICY "clinical staff create service orders" ON public.service_orders FOR INSERT
  WITH CHECK (public.is_clinical_staff(auth.uid()) AND created_by = auth.uid() AND status = 'pending_payment_approval');

DROP POLICY IF EXISTS "accounts manage billing overrides" ON public.billing_overrides;
CREATE POLICY "accounts manage billing overrides" ON public.billing_overrides FOR ALL
  USING (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'accountant'))
  WITH CHECK (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'accountant'));

DROP POLICY IF EXISTS "staff read department queues" ON public.department_queues;
CREATE POLICY "staff read department queues" ON public.department_queues FOR SELECT
  USING (
    public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'accountant')
    OR EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND lower(p.department) = lower(department))
  );

DROP POLICY IF EXISTS "staff manage own department queues" ON public.department_queues;
CREATE POLICY "staff manage own department queues" ON public.department_queues FOR UPDATE
  USING (public.has_role(auth.uid(),'admin') OR EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND lower(p.department) = lower(department)))
  WITH CHECK (public.has_role(auth.uid(),'admin') OR EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND lower(p.department) = lower(department)));

DROP POLICY IF EXISTS "staff read service order events" ON public.service_order_events;
CREATE POLICY "staff read service order events" ON public.service_order_events FOR SELECT
  USING (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'accountant') OR public.is_clinical_staff(auth.uid()));

CREATE OR REPLACE FUNCTION public.validate_service_order_insert()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.status := 'pending_payment_approval';
  NEW.payment_required := true;
  NEW.released_at := NULL;
  NEW.released_by := NULL;
  NEW.release_reason := NULL;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS service_order_insert_guard ON public.service_orders;
CREATE TRIGGER service_order_insert_guard
BEFORE INSERT ON public.service_orders
FOR EACH ROW EXECUTE FUNCTION public.validate_service_order_insert();

CREATE OR REPLACE FUNCTION public.service_order_event_trigger()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO public.service_order_events(service_order_id, from_status, to_status, actor_id, reason)
    VALUES (NEW.id, NULL, NEW.status, COALESCE(NEW.created_by, auth.uid()), 'order_created');
  ELSIF NEW.status IS DISTINCT FROM OLD.status THEN
    INSERT INTO public.service_order_events(service_order_id, from_status, to_status, actor_id, reason)
    VALUES (NEW.id, OLD.status, NEW.status, COALESCE(NEW.released_by, auth.uid()), NEW.release_reason);
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
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_order public.service_orders;
  v_paid NUMERIC(12,2) := 0;
  v_override BOOLEAN := false;
BEGIN
  IF NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'accountant')) THEN
    RAISE EXCEPTION 'Only Accounts staff can release a service order';
  END IF;

  SELECT * INTO v_order FROM public.service_orders WHERE id = _service_order_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Service order not found'; END IF;
  IF v_order.status <> 'pending_payment_approval' THEN RETURN v_order; END IF;

  SELECT COALESCE(SUM(p.amount),0) INTO v_paid
  FROM public.payments p WHERE p.invoice_id = v_order.invoice_id;
  SELECT EXISTS (SELECT 1 FROM public.billing_overrides b WHERE b.service_order_id = v_order.id) INTO v_override;

  IF v_order.invoice_id IS NOT NULL AND v_paid < v_order.amount AND NOT v_override THEN
    RAISE EXCEPTION 'Payment approval is required before release';
  END IF;

  UPDATE public.service_orders
  SET status = 'released', released_at = now(), released_by = auth.uid(), release_reason = _reason,
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
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_override public.billing_overrides;
BEGIN
  IF NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'accountant')) THEN
    RAISE EXCEPTION 'Only Accounts staff can grant billing overrides';
  END IF;
  INSERT INTO public.billing_overrides(service_order_id, reason, approved_by)
  VALUES (_service_order_id, _reason, auth.uid())
  ON CONFLICT (service_order_id) DO UPDATE
    SET reason = EXCLUDED.reason, approved_by = EXCLUDED.approved_by, approved_at = now()
  RETURNING * INTO v_override;
  RETURN v_override;
END;
$$;

CREATE OR REPLACE FUNCTION public.mark_service_order_in_progress(_service_order_id UUID)
RETURNS public.service_orders LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_order public.service_orders;
BEGIN
  IF NOT public.is_clinical_staff(auth.uid()) THEN RAISE EXCEPTION 'Clinical staff required'; END IF;
  UPDATE public.service_orders SET status='in_progress', started_at=COALESCE(started_at,now()), updated_at=now()
  WHERE id=_service_order_id AND status='released'
  RETURNING * INTO v_order;
  IF NOT FOUND THEN RAISE EXCEPTION 'Order must be released before processing'; END IF;
  RETURN v_order;
END;
$$;

CREATE OR REPLACE FUNCTION public.complete_service_order(_service_order_id UUID)
RETURNS public.service_orders LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_order public.service_orders;
BEGIN
  IF NOT public.is_clinical_staff(auth.uid()) THEN RAISE EXCEPTION 'Clinical staff required'; END IF;
  UPDATE public.service_orders SET status='completed', completed_at=now(), updated_at=now()
  WHERE id=_service_order_id AND status='in_progress'
  RETURNING * INTO v_order;
  IF NOT FOUND THEN RAISE EXCEPTION 'Order must be in progress before completion'; END IF;
  UPDATE public.department_queues SET status='completed', completed_at=now() WHERE service_order_id=_service_order_id;
  RETURN v_order;
END;
$$;

DROP TRIGGER IF EXISTS t_facility_settings_updated ON public.facility_settings;
CREATE TRIGGER t_facility_settings_updated BEFORE UPDATE ON public.facility_settings
FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();
DROP TRIGGER IF EXISTS t_service_orders_updated ON public.service_orders;
CREATE TRIGGER t_service_orders_updated BEFORE UPDATE ON public.service_orders
FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

REVOKE ALL ON FUNCTION public.release_service_order(UUID,TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.grant_service_order_override(UUID,TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.mark_service_order_in_progress(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.complete_service_order(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.release_service_order(UUID,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.grant_service_order_override(UUID,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_service_order_in_progress(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.complete_service_order(UUID) TO authenticated;
