-- Reconcile laboratory workflow around server-authoritative transitions.
-- The existing create_lab_order_with_payment_gate RPC remains the order entry point.

CREATE OR REPLACE FUNCTION public.collect_lab_sample(_lab_order_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.lab_orders%ROWTYPE;
  v_gate public.service_orders%ROWTYPE;
BEGIN
  IF NOT (public.is_clinical_staff(auth.uid()) OR public.has_role(auth.uid(),'admin')) THEN
    RAISE EXCEPTION 'Clinical staff access required';
  END IF;

  SELECT * INTO v_order FROM public.lab_orders WHERE id = _lab_order_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Laboratory order not found'; END IF;
  IF v_order.status <> 'ordered' THEN RAISE EXCEPTION 'Only ordered laboratory requests can have samples collected'; END IF;

  SELECT * INTO v_gate FROM public.service_orders
  WHERE related_entity_id = _lab_order_id AND department = 'laboratory'
  ORDER BY created_at DESC LIMIT 1;

  IF v_gate.id IS NOT NULL AND v_gate.status NOT IN ('released','in_progress','completed') THEN
    RAISE EXCEPTION 'Payment approval required before sample collection';
  END IF;

  UPDATE public.lab_orders
  SET status = 'sample_collected', collected_by = auth.uid(), sample_collected_at = now()
  WHERE id = _lab_order_id;

  RETURN jsonb_build_object('lab_order_id', _lab_order_id, 'status', 'sample_collected');
END;
$$;

CREATE OR REPLACE FUNCTION public.enter_lab_result(
  _lab_order_id UUID,
  _result_text TEXT,
  _numeric_value NUMERIC DEFAULT NULL,
  _interpretation TEXT DEFAULT NULL,
  _is_abnormal BOOLEAN DEFAULT false
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.lab_orders%ROWTYPE;
  v_catalog public.lab_test_catalogue%ROWTYPE;
  v_result UUID;
BEGIN
  IF NOT (public.is_clinical_staff(auth.uid()) OR public.has_role(auth.uid(),'admin')) THEN
    RAISE EXCEPTION 'Clinical staff access required';
  END IF;
  SELECT * INTO v_order FROM public.lab_orders WHERE id = _lab_order_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Laboratory order not found'; END IF;
  IF v_order.status <> 'sample_collected' THEN RAISE EXCEPTION 'Sample must be collected before result entry'; END IF;
  IF _result_text IS NULL OR btrim(_result_text) = '' THEN RAISE EXCEPTION 'Result value is required'; END IF;

  IF v_order.lab_test_catalogue_id IS NOT NULL THEN
    SELECT * INTO v_catalog FROM public.lab_test_catalogue WHERE id = v_order.lab_test_catalogue_id;
  END IF;

  INSERT INTO public.lab_results(
    lab_order_id, result_data, interpretation, is_abnormal, entered_by, status,
    numeric_value, unit, reference_low, reference_high, abnormal_flag
  ) VALUES (
    _lab_order_id, jsonb_build_object('value', _result_text), _interpretation, _is_abnormal,
    auth.uid(), 'completed', _numeric_value, v_catalog.unit, v_catalog.reference_low,
    v_catalog.reference_high, CASE WHEN _is_abnormal THEN 'abnormal' ELSE 'normal' END
  ) RETURNING id INTO v_result;

  UPDATE public.lab_orders SET status = 'completed' WHERE id = _lab_order_id;
  RETURN v_result;
END;
$$;

CREATE OR REPLACE FUNCTION public.approve_lab_result(_lab_result_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result public.lab_results%ROWTYPE;
BEGIN
  IF NOT (public.is_clinical_staff(auth.uid()) OR public.has_role(auth.uid(),'admin')) THEN
    RAISE EXCEPTION 'Clinical staff access required';
  END IF;
  SELECT * INTO v_result FROM public.lab_results WHERE id = _lab_result_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Laboratory result not found'; END IF;
  IF v_result.status <> 'completed' THEN RAISE EXCEPTION 'Only completed results can be approved'; END IF;

  UPDATE public.lab_results SET status = 'approved', approved_by = auth.uid(), approved_at = now() WHERE id = _lab_result_id;
  UPDATE public.lab_orders SET status = 'approved' WHERE id = v_result.lab_order_id;
  RETURN jsonb_build_object('lab_result_id', _lab_result_id, 'lab_order_id', v_result.lab_order_id, 'status', 'approved');
END;
$$;

REVOKE ALL ON FUNCTION public.collect_lab_sample(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.enter_lab_result(UUID,TEXT,NUMERIC,TEXT,BOOLEAN) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.approve_lab_result(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.collect_lab_sample(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.enter_lab_result(UUID,TEXT,NUMERIC,TEXT,BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.approve_lab_result(UUID) TO authenticated;

-- Prevent authenticated clients from bypassing the server transition functions.
REVOKE INSERT, UPDATE, DELETE ON public.lab_results FROM authenticated;
REVOKE UPDATE ON public.lab_orders FROM authenticated;
