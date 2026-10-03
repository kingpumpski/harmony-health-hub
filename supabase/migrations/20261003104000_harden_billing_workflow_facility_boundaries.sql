-- Harden billing and service-order workflow mutations at facility boundaries.
DO $migration$
DECLARE
  v_signature regprocedure;
  v_definition text;
  v_pos integer;
  v_anchor text;
BEGIN
  -- Billing override: authorization alone is not sufficient; enforce patient and order lineage.
  v_signature := 'public.grant_service_order_override(uuid,text)'::regprocedure;
  v_definition := pg_get_functiondef(v_signature);
  v_definition := replace(v_definition,
    'v_override public.billing_overrides;',
    'v_override public.billing_overrides; v_patient_facility uuid;');
  v_anchor := 'IF NOT FOUND THEN RAISE EXCEPTION ''Service order not found''; END IF;';
  IF pg_catalog.strpos(v_definition, v_anchor) = 0 THEN RAISE EXCEPTION 'grant_service_order_override anchor missing'; END IF;
  v_definition := replace(v_definition, v_anchor, v_anchor || E'
  PERFORM public.assert_patient_facility_context(v_order.patient_id);
  SELECT p.facility_id INTO v_patient_facility FROM public.patients p WHERE p.id=v_order.patient_id;
  IF v_patient_facility IS NULL OR v_order.facility_id IS DISTINCT FROM v_patient_facility THEN
    RAISE EXCEPTION ''Service order facility does not match patient facility'';
  END IF;');
  EXECUTE v_definition;
  EXECUTE format('ALTER FUNCTION %s SET search_path TO %L', v_signature, 'pg_catalog, public');
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon', v_signature);
  EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', v_signature);

  -- Billing item marking: verify invoice, patient, and every selected item belong together.
  v_signature := 'public.mark_billing_items_billed(uuid,uuid[])'::regprocedure;
  v_definition := pg_get_functiondef(v_signature);
  v_definition := replace(v_definition, 'v_count integer;', 'v_count integer; v_patient_id uuid; v_invoice_facility uuid; v_patient_facility uuid;');
  v_anchor := 'IF NOT EXISTS (SELECT 1 FROM public.invoices WHERE id = _invoice_id) THEN RAISE EXCEPTION ''Invoice not found''; END IF;';
  IF pg_catalog.strpos(v_definition, v_anchor) = 0 THEN RAISE EXCEPTION 'mark_billing_items_billed invoice anchor missing'; END IF;
  v_definition := replace(v_definition, v_anchor, 'SELECT i.patient_id,i.facility_id INTO v_patient_id,v_invoice_facility FROM public.invoices i WHERE i.id=_invoice_id FOR UPDATE; IF NOT FOUND THEN RAISE EXCEPTION ''Invoice not found''; END IF; PERFORM public.assert_patient_facility_context(v_patient_id); SELECT p.facility_id INTO v_patient_facility FROM public.patients p WHERE p.id=v_patient_id; IF v_patient_facility IS NULL OR v_invoice_facility IS DISTINCT FROM v_patient_facility THEN RAISE EXCEPTION ''Invoice facility does not match patient facility''; END IF;');
  v_anchor := 'UPDATE public.invoice_items';
  IF pg_catalog.strpos(v_definition, v_anchor) = 0 THEN RAISE EXCEPTION 'mark_billing_items_billed update anchor missing'; END IF;
  v_definition := replace(v_definition, v_anchor, 'IF EXISTS (SELECT 1 FROM public.invoice_items ii WHERE ii.invoice_id=_invoice_id AND ii.id=ANY(_item_ids) AND ii.facility_id IS DISTINCT FROM v_invoice_facility) THEN RAISE EXCEPTION ''Invoice item facility does not match invoice facility''; END IF; ' || v_anchor);
  EXECUTE v_definition;
  EXECUTE format('ALTER FUNCTION %s SET search_path TO %L', v_signature, 'pg_catalog, public');
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon', v_signature);
  EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', v_signature);

  -- Claiming service work: check facility before the status transition.
  v_signature := 'public.mark_service_order_in_progress(uuid)'::regprocedure;
  v_definition := pg_get_functiondef(v_signature);
  v_definition := replace(v_definition, 'DECLARE v_order public.service_orders;', 'DECLARE v_order public.service_orders; v_patient_facility uuid;');
  v_pos := pg_catalog.strpos(v_definition, 'BEGIN');
  IF v_pos = 0 THEN RAISE EXCEPTION 'mark_service_order_in_progress body anchor missing'; END IF;
  v_definition := substring(v_definition from 1 for v_pos + length('BEGIN') - 1) || E'
 IF auth.uid() IS NULL THEN RAISE EXCEPTION ''Authentication required''; END IF;
 SELECT so.patient_id,so.facility_id INTO v_order.patient_id,v_order.facility_id FROM public.service_orders so WHERE so.id=_service_order_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION ''Service order not found''; END IF;
 PERFORM public.assert_patient_facility_context(v_order.patient_id);
 SELECT p.facility_id INTO v_patient_facility FROM public.patients p WHERE p.id=v_order.patient_id;
 IF v_patient_facility IS NULL OR v_order.facility_id IS DISTINCT FROM v_patient_facility THEN RAISE EXCEPTION ''Service order facility does not match patient facility''; END IF;
' || substring(v_definition from v_pos + length('BEGIN'));
  EXECUTE v_definition;
  EXECUTE format('ALTER FUNCTION %s SET search_path TO %L', v_signature, 'pg_catalog, public');
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon', v_signature);
  EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', v_signature);

  -- Item payment: lock and validate the invoice and items, and preserve facility lineage
  -- when a legacy billing item needs its service order created.
  v_signature := 'public.pay_selected_invoice_items(uuid,uuid[],text,text)'::regprocedure;
  v_definition := pg_get_functiondef(v_signature);
  v_definition := replace(v_definition, 'v_method TEXT := lower(trim(coalesce(_method,'''')));',
    'v_method TEXT := lower(trim(coalesce(_method,''''))); v_patient_id uuid; v_invoice_facility uuid; v_patient_facility uuid;');
  v_anchor := 'IF NOT EXISTS (SELECT 1 FROM public.invoices WHERE id=_invoice_id) THEN RAISE EXCEPTION ''Invoice not found''; END IF;';
  IF pg_catalog.strpos(v_definition, v_anchor) = 0 THEN RAISE EXCEPTION 'pay_selected_invoice_items invoice anchor missing'; END IF;
  v_definition := replace(v_definition, v_anchor, 'SELECT i.patient_id,i.facility_id INTO v_patient_id,v_invoice_facility FROM public.invoices i WHERE i.id=_invoice_id FOR UPDATE; IF NOT FOUND THEN RAISE EXCEPTION ''Invoice not found''; END IF; PERFORM public.assert_patient_facility_context(v_patient_id); SELECT p.facility_id INTO v_patient_facility FROM public.patients p WHERE p.id=v_patient_id; IF v_patient_facility IS NULL OR v_invoice_facility IS DISTINCT FROM v_patient_facility THEN RAISE EXCEPTION ''Invoice facility does not match patient facility''; END IF;');
  v_anchor := 'IF (SELECT count(*) FROM public.invoice_items WHERE invoice_id=_invoice_id AND id=ANY(_item_ids)) <> cardinality(_item_ids) THEN RAISE EXCEPTION ''One or more selected invoice items do not belong to this invoice''; END IF;';
  IF pg_catalog.strpos(v_definition, v_anchor) = 0 THEN RAISE EXCEPTION 'pay_selected_invoice_items item membership anchor missing'; END IF;
  v_definition := replace(v_definition, v_anchor, v_anchor || E'
  IF EXISTS (SELECT 1 FROM public.invoice_items ii WHERE ii.invoice_id=_invoice_id AND ii.id=ANY(_item_ids) AND ii.facility_id IS DISTINCT FROM v_invoice_facility) THEN
    RAISE EXCEPTION ''Invoice item facility does not match invoice facility'';
  END IF;');
  v_anchor := 'INSERT INTO public.service_orders(patient_id,department,service_name,amount,related_entity_id,invoice_id,invoice_item_id,status,requested_by,service_code)';
  IF pg_catalog.strpos(v_definition, v_anchor) = 0 THEN RAISE EXCEPTION 'pay_selected_invoice_items legacy order insert anchor missing'; END IF;
  v_definition := replace(v_definition, v_anchor, 'INSERT INTO public.service_orders(patient_id,department,service_name,amount,related_entity_id,invoice_id,invoice_item_id,status,requested_by,service_code,facility_id)');
  v_anchor := 'VALUES((SELECT patient_id FROM public.invoices WHERE id=_invoice_id),item.department,item.description,item.amount,item.source_id,_invoice_id,item.id,''pending_payment_approval'',uid,item.service_code)';
  IF pg_catalog.strpos(v_definition, v_anchor) = 0 THEN RAISE EXCEPTION 'pay_selected_invoice_items legacy order values anchor missing'; END IF;
  v_definition := replace(v_definition, v_anchor, 'VALUES((SELECT patient_id FROM public.invoices WHERE id=_invoice_id),item.department,item.description,item.amount,item.source_id,_invoice_id,item.id,''pending_payment_approval'',uid,item.service_code,v_invoice_facility)');
  EXECUTE v_definition;
  EXECUTE format('ALTER FUNCTION %s SET search_path TO %L', v_signature, 'pg_catalog, public');
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon', v_signature);
  EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', v_signature);

  -- Release service order: enforce lineage before payment/override checks and release.
  v_signature := 'public.release_service_order(uuid,text)'::regprocedure;
  v_definition := pg_get_functiondef(v_signature);
  v_definition := replace(v_definition, 'uid UUID:=auth.uid();', 'uid UUID:=auth.uid(); v_patient_facility uuid; v_invoice_facility uuid;');
  v_anchor := 'IF NOT FOUND THEN RAISE EXCEPTION ''Service order not found''; END IF;';
  IF pg_catalog.strpos(v_definition, v_anchor) = 0 THEN RAISE EXCEPTION 'release_service_order order anchor missing'; END IF;
  v_definition := replace(v_definition, v_anchor, v_anchor || E'
  PERFORM public.assert_patient_facility_context(v_order.patient_id);
  SELECT p.facility_id INTO v_patient_facility FROM public.patients p WHERE p.id=v_order.patient_id;
  IF v_patient_facility IS NULL OR v_order.facility_id IS DISTINCT FROM v_patient_facility THEN
    RAISE EXCEPTION ''Service order facility does not match patient facility'';
  END IF;
  IF v_order.invoice_id IS NOT NULL THEN
    SELECT i.facility_id INTO v_invoice_facility FROM public.invoices i WHERE i.id=v_order.invoice_id AND i.patient_id=v_order.patient_id;
    IF NOT FOUND OR v_invoice_facility IS DISTINCT FROM v_patient_facility THEN
      RAISE EXCEPTION ''Service order invoice facility does not match patient facility'';
    END IF;
  END IF;
  IF v_order.invoice_item_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.invoice_items ii
    WHERE ii.id=v_order.invoice_item_id AND ii.invoice_id=v_order.invoice_id
      AND ii.facility_id=v_patient_facility
  ) THEN
    RAISE EXCEPTION ''Service order invoice item facility does not match patient facility'';
  END IF;');
  EXECUTE v_definition;
  EXECUTE format('ALTER FUNCTION %s SET search_path TO %L', v_signature, 'pg_catalog, public');
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon', v_signature);
  EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', v_signature);

  PERFORM pg_notify('pgrst', 'reload schema');
END;
$migration$;
