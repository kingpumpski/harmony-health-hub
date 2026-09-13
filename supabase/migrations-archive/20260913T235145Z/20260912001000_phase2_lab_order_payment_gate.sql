-- Phase 2: make laboratory ordering enter the same database-enforced payment gate.
-- This keeps the lab order and service order atomic so a clinical order cannot exist
-- without its corresponding payment-gated workflow record.

CREATE OR REPLACE FUNCTION public.create_lab_order_with_payment_gate(
  _patient_id UUID,
  _test_name TEXT,
  _test_category TEXT DEFAULT NULL,
  _priority TEXT DEFAULT 'routine',
  _clinical_notes TEXT DEFAULT NULL,
  _amount NUMERIC DEFAULT 0
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_lab_order_id UUID;
  v_service_order_id UUID;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  IF _patient_id IS NULL OR NULLIF(BTRIM(_test_name), '') IS NULL THEN
    RAISE EXCEPTION 'Patient and test name are required';
  END IF;

  IF COALESCE(_amount, 0) < 0 THEN
    RAISE EXCEPTION 'Amount cannot be negative';
  END IF;

  INSERT INTO public.lab_orders (
    patient_id,
    test_name,
    test_category,
    priority,
    status,
    clinical_notes,
    ordered_by
  )
  VALUES (
    _patient_id,
    BTRIM(_test_name),
    NULLIF(BTRIM(_test_category), ''),
    COALESCE(NULLIF(BTRIM(_priority), ''), 'routine'),
    'ordered',
    NULLIF(BTRIM(_clinical_notes), ''),
    auth.uid()
  )
  RETURNING id INTO v_lab_order_id;

  INSERT INTO public.service_orders (
    patient_id,
    department,
    service_name,
    amount,
    unit_price,
    payment_required,
    status,
    requested_by,
    created_by,
    related_entity_id,
    order_type,
    service_code,
    notes
  )
  VALUES (
    _patient_id,
    'laboratory',
    BTRIM(_test_name),
    COALESCE(_amount, 0),
    COALESCE(_amount, 0),
    COALESCE(_amount, 0) > 0,
    'pending_payment_approval',
    auth.uid(),
    auth.uid(),
    v_lab_order_id,
    'lab',
    NULLIF(BTRIM(_test_category), ''),
    NULLIF(BTRIM(_clinical_notes), '')
  )
  RETURNING id INTO v_service_order_id;

  RETURN jsonb_build_object(
    'lab_order_id', v_lab_order_id,
    'service_order_id', v_service_order_id,
    'status', 'pending_payment_approval'
  );
END;
$$;

REVOKE ALL ON FUNCTION public.create_lab_order_with_payment_gate(UUID, TEXT, TEXT, TEXT, TEXT, NUMERIC) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_lab_order_with_payment_gate(UUID, TEXT, TEXT, TEXT, TEXT, NUMERIC) TO authenticated;
