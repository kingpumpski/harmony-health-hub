-- Harden service-order completion/cancellation and invoice tariff adjustments
-- against cross-facility access and test-mode boundary bypasses.
DO $migration$
DECLARE
  v_signature regprocedure;
  v_definition text;
  v_pos integer;
  v_anchor text;
BEGIN
  FOREACH v_signature IN ARRAY ARRAY[
    'public.cancel_service_order(uuid,text)'::regprocedure,
    'public.complete_service_order(uuid)'::regprocedure
  ] LOOP
    v_definition := pg_get_functiondef(v_signature);

    IF v_signature = 'public.cancel_service_order(uuid,text)'::regprocedure THEN
      v_definition := replace(
        v_definition,
        'DECLARE v_order public.service_orders;',
        'DECLARE v_order public.service_orders; v_patient_id uuid; v_order_facility uuid; v_patient_facility uuid;'
      );
    ELSE
      v_definition := replace(
        v_definition,
        'DECLARE v_order public.service_orders;',
        'DECLARE v_order public.service_orders; v_patient_id uuid; v_order_facility uuid; v_patient_facility uuid;'
      );
    END IF;

    v_pos := pg_catalog.strpos(v_definition, 'BEGIN');
    IF v_pos = 0 THEN
      RAISE EXCEPTION 'Could not locate function body for %', v_signature;
    END IF;

    v_definition :=
      substring(v_definition from 1 for v_pos + length('BEGIN') - 1)
      || E'
  IF auth.uid() IS NULL THEN RAISE EXCEPTION ''Authentication required''; END IF;
  SELECT so.patient_id, so.facility_id
    INTO v_patient_id, v_order_facility
  FROM public.service_orders so
  WHERE so.id = _service_order_id
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION ''Service order not found''; END IF;
  PERFORM public.assert_patient_facility_context(v_patient_id);
  SELECT p.facility_id INTO v_patient_facility
  FROM public.patients p WHERE p.id = v_patient_id;
  IF v_patient_facility IS NULL OR v_order_facility IS DISTINCT FROM v_patient_facility THEN
    RAISE EXCEPTION ''Service order facility does not match patient facility'';
  END IF;
'
      || substring(v_definition from v_pos + length('BEGIN'));

    EXECUTE v_definition;
    EXECUTE format('ALTER FUNCTION %s SET search_path TO %L', v_signature, '');
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon', v_signature);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', v_signature);
  END LOOP;

  v_signature := 'public.adjust_invoice_item_tariff(uuid,numeric,text,text)'::regprocedure;
  v_definition := pg_get_functiondef(v_signature);

  v_anchor := 'SELECT ii.*, i.status AS invoice_status, i.patient_id';
  IF pg_catalog.strpos(v_definition, v_anchor) = 0 THEN
    RAISE EXCEPTION 'Could not locate invoice tariff query';
  END IF;
  v_definition := replace(v_definition, v_anchor,
    'SELECT ii.*, i.status AS invoice_status, i.patient_id, i.facility_id AS invoice_facility_id');

  v_anchor := 'IF item.id IS NULL THEN RAISE EXCEPTION ''Invoice item not found''; END IF;';
  IF pg_catalog.strpos(v_definition, v_anchor) = 0 THEN
    RAISE EXCEPTION 'Could not locate invoice item existence check';
  END IF;
  v_definition := replace(v_definition, v_anchor, v_anchor || E'
  PERFORM public.assert_patient_facility_context(item.patient_id);
  IF item.facility_id IS DISTINCT FROM item.invoice_facility_id
     OR item.facility_id IS DISTINCT FROM (
       SELECT p.facility_id FROM public.patients p WHERE p.id = item.patient_id
     ) THEN
    RAISE EXCEPTION ''Invoice, invoice item, and patient facility attribution must match'';
  END IF;');

  v_anchor := 'WHERE s.invoice_item_id=item.id AND s.status<>''cancelled''';
  IF pg_catalog.strpos(v_definition, v_anchor) = 0 THEN
    RAISE EXCEPTION 'Could not locate linked service-order query';
  END IF;
  v_definition := replace(v_definition, v_anchor,
    'WHERE s.invoice_item_id=item.id AND s.facility_id=item.facility_id AND s.status<>''cancelled''');

  EXECUTE v_definition;
  EXECUTE format('ALTER FUNCTION %s SET search_path = ''pg_catalog, public''', v_signature);
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon', v_signature);
  EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', v_signature);

  PERFORM pg_notify('pgrst', 'reload schema');
END;
$migration$;
