-- Keep the service-order billing boundary aligned with production and the
-- authenticated workflow contract. This is additive/idempotent and does not
-- introduce payment_status/fulfillment_status columns.

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

  SELECT * INTO v_order
  FROM public.service_orders
  WHERE id = _service_order_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Service order not found';
  END IF;
  IF v_order.status <> 'pending_payment_approval' THEN
    RAISE EXCEPTION 'Billing override is only available before service release';
  END IF;

  INSERT INTO public.billing_overrides(
    service_order_id, patient_id, department, related_entity_id,
    reason, overridden_by, approved_by, approved_at
  )
  VALUES (
    v_order.id, v_order.patient_id, v_order.department, v_order.related_entity_id,
    trim(_reason), auth.uid(), auth.uid(), now()
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
  IF NOT (
    public.has_role(auth.uid(),'admin')
    OR public.has_role(auth.uid(),'accountant')
    OR public.has_role(auth.uid(),'front_desk')
  ) THEN
    RAISE EXCEPTION 'Only authorized billing staff can release a service order';
  END IF;

  SELECT * INTO v_order
  FROM public.service_orders
  WHERE id = _service_order_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Service order not found';
  END IF;
  IF v_order.status <> 'pending_payment_approval' THEN
    RETURN v_order;
  END IF;

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
  SET status='released',
      approved_at=now(), approved_by=auth.uid(),
      released_at=now(), released_by=auth.uid(),
      release_reason=_reason, updated_at=now()
  WHERE id=v_order.id
  RETURNING * INTO v_order;

  INSERT INTO public.department_queues(
    service_order_id, patient_id, department, related_encounter_id,
    related_invoice_id, payment_required, payment_satisfied, priority,
    reason, created_by, queued_at, status
  )
  VALUES(
    v_order.id, v_order.patient_id, v_order.department, v_order.encounter_id,
    v_order.invoice_id, v_order.payment_required, true, 'normal',
    v_order.service_name, auth.uid(), now(), 'queued'
  )
  ON CONFLICT (service_order_id) DO UPDATE
    SET payment_satisfied=true,
        status=CASE WHEN public.department_queues.status='cancelled' THEN 'queued' ELSE public.department_queues.status END,
        updated_at=now();

  RETURN v_order;
END;
$$;

REVOKE ALL ON FUNCTION public.grant_service_order_override(UUID,TEXT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.release_service_order(UUID,TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.grant_service_order_override(UUID,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.release_service_order(UUID,TEXT) TO authenticated;

NOTIFY pgrst, 'reload schema';
