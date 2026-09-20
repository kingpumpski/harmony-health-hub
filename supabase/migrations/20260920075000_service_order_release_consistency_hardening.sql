-- Final service-order release consistency boundary.
CREATE OR REPLACE FUNCTION public.release_service_order(_service_order_id UUID,_reason TEXT DEFAULT 'Payment received')
RETURNS public.service_orders LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_order public.service_orders; v_paid NUMERIC(12,2):=0; v_override BOOLEAN:=false; v_has_item_link BOOLEAN:=false; uid UUID:=auth.uid();
BEGIN
  IF uid IS NULL OR NOT(public.has_role(uid,'admin') OR public.has_role(uid,'accountant') OR public.has_role(uid,'front_desk')) THEN RAISE EXCEPTION 'Only authorized billing staff can release a service order'; END IF;
  SELECT * INTO v_order FROM public.service_orders WHERE id=_service_order_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Service order not found'; END IF;
  IF v_order.status<>'pending_payment_approval' THEN RETURN v_order; END IF;
  IF v_order.amount<0 THEN RAISE EXCEPTION 'Service order amount cannot be negative'; END IF;
  IF v_order.invoice_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.invoices WHERE id=v_order.invoice_id AND patient_id=v_order.patient_id) THEN RAISE EXCEPTION 'Service order invoice does not belong to the patient'; END IF;
  v_has_item_link:=v_order.invoice_item_id IS NOT NULL;
  IF v_has_item_link THEN
    IF NOT EXISTS(SELECT 1 FROM public.invoice_items ii WHERE ii.id=v_order.invoice_item_id AND ii.invoice_id=v_order.invoice_id) THEN RAISE EXCEPTION 'Service order invoice item does not match invoice'; END IF;
    SELECT COALESCE(SUM(ip.amount),0) INTO v_paid FROM public.invoice_item_payments ip WHERE ip.invoice_item_id=v_order.invoice_item_id;
  ELSIF v_order.invoice_id IS NOT NULL THEN
    SELECT COALESCE(SUM(p.amount),0) INTO v_paid FROM public.payments p WHERE p.invoice_id=v_order.invoice_id AND (p.paid_at IS NOT NULL OR lower(COALESCE(p.status,'')) IN('paid','completed','confirmed','success','successful'));
  END IF;
  IF v_paid<0 THEN RAISE EXCEPTION 'Payment total cannot be negative'; END IF;
  SELECT EXISTS(SELECT 1 FROM public.billing_overrides b WHERE b.service_order_id=v_order.id) INTO v_override;
  IF v_order.payment_required AND v_order.amount>0 AND (v_order.invoice_id IS NULL OR v_paid<v_order.amount) AND NOT v_override THEN RAISE EXCEPTION 'Payment approval is required before release'; END IF;
  UPDATE public.service_orders SET status='released',approved_at=now(),approved_by=uid,released_at=now(),released_by=uid,release_reason=_reason,updated_at=now() WHERE id=v_order.id AND status='pending_payment_approval' RETURNING * INTO v_order;
  IF NOT FOUND THEN SELECT * INTO v_order FROM public.service_orders WHERE id=_service_order_id; RETURN v_order; END IF;
  INSERT INTO public.department_queues(service_order_id,patient_id,department,related_encounter_id,related_invoice_id,payment_required,payment_satisfied,priority,reason,created_by,queued_at,status)
  VALUES(v_order.id,v_order.patient_id,v_order.department,v_order.encounter_id,v_order.invoice_id,v_order.payment_required,true,'normal',v_order.service_name,uid,now(),'queued')
  ON CONFLICT(service_order_id) DO UPDATE SET payment_satisfied=true,status=CASE WHEN public.department_queues.status='cancelled' THEN 'queued' ELSE public.department_queues.status END,updated_at=now();
  PERFORM public.record_system_audit('service_order_released','billing','service_order',v_order.id,'info',jsonb_build_object('patient_id',v_order.patient_id,'invoice_id',v_order.invoice_id,'invoice_item_id',v_order.invoice_item_id,'payment_satisfied_amount',v_paid,'override_used',v_override,'reason',_reason));
  RETURN v_order;
END; $$;
REVOKE ALL ON FUNCTION public.release_service_order(UUID,TEXT) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.release_service_order(UUID,TEXT) TO authenticated;
NOTIFY pgrst,'reload schema';
