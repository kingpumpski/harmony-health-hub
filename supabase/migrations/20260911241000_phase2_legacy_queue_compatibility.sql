-- Compatibility layer for legacy billing_overrides and department_queues tables.
-- These tables predate Phase 2 and must be extended rather than recreated.

ALTER TABLE public.billing_overrides
  ADD COLUMN IF NOT EXISTS service_order_id UUID,
  ADD COLUMN IF NOT EXISTS approved_by UUID,
  ADD COLUMN IF NOT EXISTS approved_at TIMESTAMPTZ;

UPDATE public.billing_overrides
SET approved_by = COALESCE(approved_by, overridden_by),
    approved_at = COALESCE(approved_at, created_at)
WHERE approved_by IS NULL;

ALTER TABLE public.billing_overrides
  ALTER COLUMN approved_by SET NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'billing_overrides_service_order_fk'
  ) THEN
    ALTER TABLE public.billing_overrides
      ADD CONSTRAINT billing_overrides_service_order_fk
      FOREIGN KEY (service_order_id)
      REFERENCES public.service_orders(id)
      ON DELETE CASCADE;
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_billing_overrides_service_order
  ON public.billing_overrides(service_order_id)
  WHERE service_order_id IS NOT NULL;

ALTER TABLE public.department_queues
  ADD COLUMN IF NOT EXISTS service_order_id UUID,
  ADD COLUMN IF NOT EXISTS queued_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS claimed_by UUID,
  ADD COLUMN IF NOT EXISTS claimed_at TIMESTAMPTZ;

UPDATE public.department_queues
SET queued_at = COALESCE(queued_at, created_at),
    claimed_by = COALESCE(claimed_by, assigned_to),
    payment_required = COALESCE(payment_required, true),
    payment_satisfied = COALESCE(payment_satisfied, false)
WHERE queued_at IS NULL OR claimed_by IS NULL;

ALTER TABLE public.department_queues
  ALTER COLUMN queued_at SET DEFAULT now();

ALTER TABLE public.department_queues
  ALTER COLUMN queued_at SET NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'department_queues_service_order_fk'
  ) THEN
    ALTER TABLE public.department_queues
      ADD CONSTRAINT department_queues_service_order_fk
      FOREIGN KEY (service_order_id)
      REFERENCES public.service_orders(id)
      ON DELETE CASCADE;
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_department_queues_service_order
  ON public.department_queues(service_order_id)
  WHERE service_order_id IS NOT NULL;

-- Replace the Phase 2 RPCs so they populate the legacy required columns too.
CREATE OR REPLACE FUNCTION public.grant_service_order_override(_service_order_id UUID, _reason TEXT)
RETURNS public.billing_overrides
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.service_orders;
  v_override public.billing_overrides;
BEGIN
  IF NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'accountant')) THEN
    RAISE EXCEPTION 'Only Accounts staff can grant billing overrides';
  END IF;
  IF length(trim(COALESCE(_reason,''))) < 3 THEN
    RAISE EXCEPTION 'An override reason of at least 3 characters is required';
  END IF;

  SELECT * INTO v_order FROM public.service_orders WHERE id = _service_order_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Service order not found'; END IF;

  INSERT INTO public.billing_overrides(
    service_order_id,
    patient_id,
    department,
    related_entity_id,
    reason,
    overridden_by,
    approved_by,
    approved_at
  )
  VALUES (
    v_order.id,
    v_order.patient_id,
    v_order.department,
    v_order.related_entity_id,
    trim(_reason),
    auth.uid(),
    auth.uid(),
    now()
  )
  ON CONFLICT (service_order_id) DO UPDATE
    SET patient_id = EXCLUDED.patient_id,
        department = EXCLUDED.department,
        related_entity_id = EXCLUDED.related_entity_id,
        reason = EXCLUDED.reason,
        overridden_by = EXCLUDED.overridden_by,
        approved_by = EXCLUDED.approved_by,
        approved_at = EXCLUDED.approved_at
  RETURNING * INTO v_override;

  RETURN v_override;
END;
$$;

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

  INSERT INTO public.department_queues(
    service_order_id,
    patient_id,
    department,
    related_encounter_id,
    related_invoice_id,
    payment_required,
    payment_satisfied,
    priority,
    reason,
    created_by,
    queued_at,
    status
  )
  VALUES (
    v_order.id,
    v_order.patient_id,
    v_order.department,
    v_order.encounter_id,
    v_order.invoice_id,
    v_order.payment_required,
    true,
    'normal',
    v_order.service_name,
    auth.uid(),
    now(),
    'queued'
  )
  ON CONFLICT (service_order_id) DO UPDATE
    SET payment_satisfied = true,
        status = CASE WHEN public.department_queues.status = 'cancelled' THEN 'queued' ELSE public.department_queues.status END,
        updated_at = now();

  RETURN v_order;
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
  UPDATE public.department_queues
  SET status='cancelled', updated_at=now()
  WHERE service_order_id=v_order.id;
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
  SET status='claimed',
      claimed_by=auth.uid(),
      assigned_to=auth.uid(),
      claimed_at=COALESCE(claimed_at,now()),
      updated_at=now()
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
  SET status='completed', completed_at=now(), updated_at=now()
  WHERE service_order_id=_service_order_id;
  RETURN v_order;
END;
$$;

GRANT EXECUTE ON FUNCTION public.grant_service_order_override(UUID,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.release_service_order(UUID,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.cancel_service_order(UUID,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_service_order_in_progress(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.complete_service_order(UUID) TO authenticated;
