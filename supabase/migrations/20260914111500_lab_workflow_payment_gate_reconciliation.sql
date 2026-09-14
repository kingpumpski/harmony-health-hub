-- Reconcile laboratory transitions with the server-authoritative payment gate.
-- Existing RPC signatures are intentionally preserved for client compatibility.

CREATE OR REPLACE FUNCTION public.collect_lab_sample(_lab_order_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_order public.lab_orders%ROWTYPE;
  v_gate public.service_orders%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication is required'; END IF;
  IF NOT (public.is_clinical_staff(v_uid) OR public.has_role(v_uid,'admin')) THEN
    RAISE EXCEPTION 'Clinical staff access required';
  END IF;

  SELECT * INTO v_order FROM public.lab_orders WHERE id = _lab_order_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Laboratory order not found'; END IF;
  IF v_order.status <> 'ordered' THEN
    RAISE EXCEPTION 'Only released laboratory requests can have samples collected';
  END IF;

  SELECT * INTO v_gate
  FROM public.service_orders
  WHERE related_entity_id = _lab_order_id AND department = 'laboratory'
  ORDER BY created_at DESC LIMIT 1;

  IF v_gate.id IS NOT NULL AND v_gate.status NOT IN ('released','in_progress','completed') THEN
    RAISE EXCEPTION 'Payment approval required before sample collection';
  END IF;

  UPDATE public.lab_orders
  SET status = 'sample_collected', collected_by = v_uid, sample_collected_at = now(), updated_at = now()
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
  v_uid UUID := auth.uid();
  v_order public.lab_orders%ROWTYPE;
  v_catalog public.lab_test_catalogue%ROWTYPE;
  v_result UUID;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication is required'; END IF;
  IF NOT (public.is_clinical_staff(v_uid) OR public.has_role(v_uid,'admin')) THEN
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
    v_uid, 'completed', _numeric_value, v_catalog.unit, v_catalog.reference_low,
    v_catalog.reference_high, CASE WHEN _is_abnormal THEN 'abnormal' ELSE 'normal' END
  ) RETURNING id INTO v_result;

  UPDATE public.lab_orders SET status = 'completed', updated_at = now() WHERE id = _lab_order_id;
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
  v_uid UUID := auth.uid();
  v_result public.lab_results%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication is required'; END IF;
  IF NOT (public.is_clinical_staff(v_uid) OR public.has_role(v_uid,'admin')) THEN
    RAISE EXCEPTION 'Clinical staff access required';
  END IF;

  SELECT * INTO v_result FROM public.lab_results WHERE id = _lab_result_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Laboratory result not found'; END IF;
  IF v_result.status <> 'completed' THEN RAISE EXCEPTION 'Only completed results can be approved'; END IF;

  UPDATE public.lab_results
  SET status = 'approved', approved_by = v_uid, approved_at = now(), updated_at = now()
  WHERE id = _lab_result_id;
  UPDATE public.lab_orders SET status = 'approved', updated_at = now() WHERE id = v_result.lab_order_id;

  RETURN jsonb_build_object('lab_result_id', _lab_result_id, 'lab_order_id', v_result.lab_order_id, 'status', 'approved');
END;
$$;

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
  v_uid UUID := auth.uid();
  v_lab_order_id UUID;
  v_service_order_id UUID;
  v_requires_payment BOOLEAN := COALESCE(_amount,0) > 0;
  v_service_status TEXT := CASE WHEN v_requires_payment THEN 'pending_payment_approval' ELSE 'released' END;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication is required'; END IF;
  IF NOT (public.has_role(v_uid,'admin') OR public.has_role(v_uid,'practitioner') OR public.has_role(v_uid,'nurse') OR public.has_role(v_uid,'midwife') OR public.has_role(v_uid,'lab_technician') OR public.has_role(v_uid,'front_desk')) THEN
    RAISE EXCEPTION 'Laboratory order access required';
  END IF;
  IF _patient_id IS NULL OR NULLIF(btrim(_test_name),'') IS NULL THEN RAISE EXCEPTION 'Patient and test name are required'; END IF;
  IF COALESCE(_amount,0) < 0 THEN RAISE EXCEPTION 'Amount cannot be negative'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.patients WHERE id = _patient_id) THEN RAISE EXCEPTION 'Patient not found'; END IF;

  INSERT INTO public.lab_orders(patient_id,test_name,test_category,priority,status,clinical_notes,ordered_by)
  VALUES(_patient_id,btrim(_test_name),NULLIF(btrim(_test_category),''),COALESCE(NULLIF(btrim(_priority),''),'routine'),'ordered',NULLIF(btrim(_clinical_notes),''),v_uid)
  RETURNING id INTO v_lab_order_id;

  INSERT INTO public.service_orders(patient_id,department,service_name,amount,unit_price,payment_required,status,requested_by,created_by,related_entity_id,order_type,service_code,notes)
  VALUES(_patient_id,'laboratory',btrim(_test_name),COALESCE(_amount,0),COALESCE(_amount,0),v_requires_payment,v_service_status,v_uid,v_uid,v_lab_order_id,'lab',NULLIF(btrim(_test_category),''),NULLIF(btrim(_clinical_notes),''))
  RETURNING id INTO v_service_order_id;

  RETURN jsonb_build_object('lab_order_id',v_lab_order_id,'service_order_id',v_service_order_id,'status',v_service_status);
END;
$$;

REVOKE ALL ON FUNCTION public.collect_lab_sample(UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.enter_lab_result(UUID,TEXT,NUMERIC,TEXT,BOOLEAN) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.approve_lab_result(UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.create_lab_order_with_payment_gate(UUID,TEXT,TEXT,TEXT,TEXT,NUMERIC) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.collect_lab_sample(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.enter_lab_result(UUID,TEXT,NUMERIC,TEXT,BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.approve_lab_result(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_lab_order_with_payment_gate(UUID,TEXT,TEXT,TEXT,TEXT,NUMERIC) TO authenticated;
