SELECT 1;
-- Idempotent production RPC compatibility hotfix.
CREATE OR REPLACE FUNCTION public.create_admission_workflow(_patient_id UUID, _ward TEXT, _bed TEXT DEFAULT NULL, _reason TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_id UUID;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife')) THEN RAISE EXCEPTION 'Admission creation is not permitted'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.patients WHERE id=_patient_id) THEN RAISE EXCEPTION 'Patient not found'; END IF;
  IF _ward IS NULL OR btrim(_ward)='' THEN RAISE EXCEPTION 'Ward is required'; END IF;
  INSERT INTO public.admissions(patient_id,ward,bed,reason,admitted_by,status,admitted_at) VALUES (_patient_id,btrim(_ward),NULLIF(btrim(_bed),''),NULLIF(btrim(_reason),''),auth.uid(),'admitted',now()) RETURNING id INTO v_id;
  RETURN jsonb_build_object('admission_id',v_id,'status','admitted');
END; $$;

CREATE OR REPLACE FUNCTION public.get_missing_billing_tariffs(_patient_id UUID DEFAULT NULL)
RETURNS TABLE(invoice_item_id UUID,invoice_id UUID,patient_id UUID,description TEXT,department TEXT,service_code TEXT,quantity INTEGER,unit_price NUMERIC,amount NUMERIC,service_order_id UUID,service_order_status TEXT,created_at TIMESTAMPTZ)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'accountant') OR public.has_role(auth.uid(),'front_desk')) THEN RAISE EXCEPTION 'Billing access denied'; END IF;
  RETURN QUERY SELECT ii.id,ii.invoice_id,i.patient_id,ii.description,ii.department,ii.service_code,ii.quantity,ii.unit_price,ii.amount,so.id,so.status,ii.created_at
  FROM public.invoice_items ii JOIN public.invoices i ON i.id=ii.invoice_id
  LEFT JOIN LATERAL (SELECT s.id,s.status FROM public.service_orders s WHERE s.invoice_item_id=ii.id AND s.status<>'cancelled' ORDER BY s.created_at DESC LIMIT 1) so ON true
  WHERE ii.amount<=0 AND ii.unit_price<=0 AND i.status IN ('pending','partially_paid') AND (_patient_id IS NULL OR i.patient_id=_patient_id) ORDER BY ii.created_at DESC;
END; $$;

CREATE OR REPLACE FUNCTION public.grant_service_order_override(_service_order_id UUID,_reason TEXT)
RETURNS public.billing_overrides LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_order public.service_orders; v_override public.billing_overrides;
BEGIN
  IF NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'accountant')) THEN RAISE EXCEPTION 'Only Accounts staff can grant billing overrides'; END IF;
  IF length(trim(COALESCE(_reason,'')))<3 THEN RAISE EXCEPTION 'An override reason of at least 3 characters is required'; END IF;
  SELECT * INTO v_order FROM public.service_orders WHERE id=_service_order_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Service order not found'; END IF;
  IF v_order.status<>'pending_payment_approval' THEN RAISE EXCEPTION 'Billing override is only available before service release'; END IF;
  INSERT INTO public.billing_overrides(service_order_id,patient_id,department,related_entity_id,reason,overridden_by,approved_by,approved_at)
  VALUES(v_order.id,v_order.patient_id,v_order.department,v_order.related_entity_id,trim(_reason),auth.uid(),auth.uid(),now())
  ON CONFLICT(service_order_id) DO UPDATE SET patient_id=EXCLUDED.patient_id,department=EXCLUDED.department,related_entity_id=EXCLUDED.related_entity_id,reason=EXCLUDED.reason,overridden_by=EXCLUDED.overridden_by,approved_by=EXCLUDED.approved_by,approved_at=EXCLUDED.approved_at
  RETURNING * INTO v_override;
  RETURN v_override;
END; $$;

CREATE OR REPLACE FUNCTION public.release_service_order(_service_order_id UUID,_reason TEXT DEFAULT 'Payment received')
RETURNS public.service_orders LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_order public.service_orders; v_paid NUMERIC(12,2):=0; v_override BOOLEAN:=false; v_encounter_status TEXT;
BEGIN
  IF auth.uid() IS NULL OR NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'accountant') OR public.has_role(auth.uid(),'front_desk')) THEN RAISE EXCEPTION 'Accounts release permission required'; END IF;
  SELECT * INTO v_order FROM public.service_orders WHERE id=_service_order_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Service order not found'; END IF;
  IF v_order.encounter_id IS NOT NULL THEN
    SELECT status INTO v_encounter_status FROM public.encounters WHERE id=v_order.encounter_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Linked encounter not found'; END IF;
    IF v_encounter_status IN ('completed','cancelled') THEN RAISE EXCEPTION 'Cannot release a service order linked to a completed or cancelled encounter'; END IF;
  END IF;
  IF v_order.status<>'pending_payment_approval' THEN RETURN v_order; END IF;
  SELECT COALESCE(SUM(p.amount),0) INTO v_paid FROM public.payments p WHERE p.invoice_id=v_order.invoice_id AND (p.paid_at IS NOT NULL OR lower(COALESCE(p.status,'')) IN ('paid','completed','confirmed','success','successful'));
  SELECT EXISTS(SELECT 1 FROM public.billing_overrides b WHERE b.service_order_id=v_order.id) INTO v_override;
  IF v_order.payment_required AND v_order.amount>0 AND (v_order.invoice_id IS NULL OR v_paid<v_order.amount) AND NOT v_override THEN RAISE EXCEPTION 'Payment approval is required before release'; END IF;
  UPDATE public.service_orders SET status='released',approved_at=now(),approved_by=auth.uid(),updated_at=now() WHERE id=v_order.id AND status='pending_payment_approval' RETURNING * INTO v_order;
  INSERT INTO public.department_queues(service_order_id,patient_id,department,related_encounter_id,related_invoice_id,payment_required,payment_satisfied,priority,reason,created_by,queued_at,status)
  VALUES(v_order.id,v_order.patient_id,v_order.department,v_order.encounter_id,v_order.invoice_id,v_order.payment_required,true,'normal',v_order.service_name,auth.uid(),now(),'queued')
  ON CONFLICT(service_order_id) DO UPDATE SET payment_satisfied=true,status=CASE WHEN public.department_queues.status='cancelled' THEN 'queued' ELSE public.department_queues.status END,updated_at=now();
  IF v_order.order_type='imaging' AND v_order.related_entity_id IS NOT NULL THEN UPDATE public.imaging_orders SET status='released',updated_at=now() WHERE id=v_order.related_entity_id AND service_order_id=v_order.id AND status='pending_payment_approval'; END IF;
  RETURN v_order;
END; $$;

CREATE OR REPLACE FUNCTION public.enter_lab_result(_lab_order_id UUID,_result_text TEXT,_numeric_value NUMERIC DEFAULT NULL,_interpretation TEXT DEFAULT NULL,_is_abnormal BOOLEAN DEFAULT false)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_uid UUID:=auth.uid(); v_order public.lab_orders%ROWTYPE; v_catalog public.lab_test_catalogue%ROWTYPE; v_result UUID;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication is required'; END IF;
  IF NOT (public.is_clinical_staff(v_uid) OR public.has_role(v_uid,'admin')) THEN RAISE EXCEPTION 'Clinical staff access required'; END IF;
  SELECT * INTO v_order FROM public.lab_orders WHERE id=_lab_order_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Laboratory order not found'; END IF;
  IF v_order.status<>'sample_collected' THEN RAISE EXCEPTION 'Sample must be collected before result entry'; END IF;
  IF _result_text IS NULL OR btrim(_result_text)='' THEN RAISE EXCEPTION 'Result value is required'; END IF;
  IF v_order.lab_test_catalogue_id IS NOT NULL THEN SELECT * INTO v_catalog FROM public.lab_test_catalogue WHERE id=v_order.lab_test_catalogue_id; END IF;
  INSERT INTO public.lab_results(lab_order_id,result_data,interpretation,is_abnormal,entered_by,status,numeric_value,unit,reference_low,reference_high,abnormal_flag)
  VALUES(_lab_order_id,jsonb_build_object('value',_result_text),_interpretation,_is_abnormal,v_uid,'completed',_numeric_value,v_catalog.unit,v_catalog.reference_low,v_catalog.reference_high,CASE WHEN _is_abnormal THEN 'abnormal' ELSE 'normal' END) RETURNING id INTO v_result;
  UPDATE public.lab_orders SET status='completed',updated_at=now() WHERE id=_lab_order_id;
  RETURN v_result;
END; $$;

REVOKE ALL ON FUNCTION public.create_admission_workflow(UUID,TEXT,TEXT,TEXT) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.get_missing_billing_tariffs(UUID) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.grant_service_order_override(UUID,TEXT) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.release_service_order(UUID,TEXT) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.enter_lab_result(UUID,TEXT,NUMERIC,TEXT,BOOLEAN) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.create_admission_workflow(UUID,TEXT,TEXT,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_missing_billing_tariffs(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.grant_service_order_override(UUID,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.release_service_order(UUID,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.enter_lab_result(UUID,TEXT,NUMERIC,TEXT,BOOLEAN) TO authenticated;
NOTIFY pgrst,'reload schema';
