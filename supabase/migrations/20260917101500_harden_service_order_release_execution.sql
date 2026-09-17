-- Align production service-order release with the current payment/encounter lifecycle contract.
-- This migration is additive/idempotent and preserves the authenticated RPC signature.

CREATE OR REPLACE FUNCTION public.release_service_order(
  _service_order_id uuid,
  _reason text DEFAULT 'Payment received'
)
RETURNS public.service_orders
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.service_orders;
  v_paid numeric(12,2) := 0;
  v_override boolean := false;
  v_encounter_status text;
BEGIN
  IF auth.uid() IS NULL OR NOT (
    public.has_role(auth.uid(),'admin') OR
    public.has_role(auth.uid(),'accountant') OR
    public.has_role(auth.uid(),'front_desk')
  ) THEN
    RAISE EXCEPTION 'Accounts release permission required';
  END IF;

  SELECT * INTO v_order
  FROM public.service_orders
  WHERE id = _service_order_id
  FOR UPDATE;

  IF NOT FOUND THEN RAISE EXCEPTION 'Service order not found'; END IF;

  IF v_order.encounter_id IS NOT NULL THEN
    SELECT status INTO v_encounter_status
    FROM public.encounters
    WHERE id = v_order.encounter_id;

    IF NOT FOUND THEN RAISE EXCEPTION 'Linked encounter not found'; END IF;
    IF v_encounter_status IN ('completed','cancelled') THEN
      RAISE EXCEPTION 'Cannot release a service order linked to a completed or cancelled encounter';
    END IF;
  END IF;

  IF v_order.status <> 'pending_payment_approval' THEN
    RETURN v_order;
  END IF;

  SELECT COALESCE(SUM(p.amount),0)
    INTO v_paid
  FROM public.payments p
  WHERE p.invoice_id = v_order.invoice_id
    AND (
      p.paid_at IS NOT NULL
      OR lower(COALESCE(p.status,'')) IN ('paid','completed','confirmed','success','successful')
    );

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
  SET status='released', approved_at=now(), approved_by=auth.uid(), updated_at=now()
  WHERE id=v_order.id AND status='pending_payment_approval'
  RETURNING * INTO v_order;

  IF NOT FOUND THEN
    SELECT * INTO v_order FROM public.service_orders WHERE id=_service_order_id;
    RETURN v_order;
  END IF;

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

  IF v_order.order_type = 'imaging' AND v_order.related_entity_id IS NOT NULL THEN
    UPDATE public.imaging_orders
    SET status='released', updated_at=now()
    WHERE id=v_order.related_entity_id
      AND service_order_id=v_order.id
      AND status='pending_payment_approval';
  END IF;

  RETURN v_order;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.release_service_order(uuid,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.release_service_order(uuid,text) TO authenticated;
NOTIFY pgrst, 'reload schema';
