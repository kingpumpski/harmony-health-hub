-- Harden laboratory lifecycle identity, payment and replay boundaries.
CREATE OR REPLACE FUNCTION public.collect_lab_sample(_lab_order_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE uid UUID:=auth.uid(); o public.lab_orders%ROWTYPE; g public.service_orders%ROWTYPE;
BEGIN
 IF uid IS NULL OR NOT(public.has_role(uid,'admin') OR public.has_role(uid,'lab_technician') OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse') OR public.has_role(uid,'midwife') OR public.has_role(uid,'specialist_nurse')) THEN RAISE EXCEPTION 'Laboratory clinical role required'; END IF;
 SELECT * INTO o FROM public.lab_orders WHERE id=_lab_order_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Laboratory order not found'; END IF;
 IF o.status<>'ordered' THEN RAISE EXCEPTION 'Only ordered laboratory requests can have samples collected'; END IF;
 SELECT * INTO g FROM public.service_orders WHERE related_entity_id=o.id AND department='laboratory' AND patient_id=o.patient_id ORDER BY created_at DESC LIMIT 1 FOR UPDATE;
 IF g.id IS NOT NULL AND g.status NOT IN('released','in_progress','completed') THEN RAISE EXCEPTION 'Payment approval required before sample collection'; END IF;
 UPDATE public.lab_orders SET status='sample_collected',collected_by=uid,sample_collected_at=now(),updated_at=now() WHERE id=o.id;
 RETURN jsonb_build_object('lab_order_id',o.id,'status','sample_collected');
END; $$;

CREATE OR REPLACE FUNCTION public.enter_lab_result(_lab_order_id UUID,_result_text TEXT,_numeric_value NUMERIC DEFAULT NULL,_interpretation TEXT DEFAULT NULL,_is_abnormal BOOLEAN DEFAULT false)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE uid UUID:=auth.uid(); o public.lab_orders%ROWTYPE; c public.lab_test_catalogue%ROWTYPE; rid UUID;
BEGIN
 IF uid IS NULL OR NOT(public.has_role(uid,'admin') OR public.has_role(uid,'lab_technician')) THEN RAISE EXCEPTION 'Laboratory technician role required'; END IF;
 SELECT * INTO o FROM public.lab_orders WHERE id=_lab_order_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Laboratory order not found'; END IF;
 IF o.status<>'sample_collected' THEN RAISE EXCEPTION 'Sample must be collected before result entry'; END IF;
 IF NULLIF(btrim(_result_text),'') IS NULL THEN RAISE EXCEPTION 'Result value is required'; END IF;
 IF EXISTS(SELECT 1 FROM public.lab_results WHERE lab_order_id=o.id AND status IN('completed','approved')) THEN RAISE EXCEPTION 'A completed result already exists for this laboratory order'; END IF;
 IF o.lab_test_catalogue_id IS NOT NULL THEN SELECT * INTO c FROM public.lab_test_catalogue WHERE id=o.lab_test_catalogue_id; END IF;
 INSERT INTO public.lab_results(lab_order_id,result_data,interpretation,is_abnormal,entered_by,status,numeric_value,unit,reference_low,reference_high,abnormal_flag)
 VALUES(o.id,jsonb_build_object('value',_result_text),_interpretation,_is_abnormal,uid,'completed',_numeric_value,c.unit,c.reference_low,c.reference_high,CASE WHEN _is_abnormal THEN 'abnormal' ELSE 'normal' END)
 RETURNING id INTO rid;
 UPDATE public.lab_orders SET status='completed',updated_at=now() WHERE id=o.id;
 RETURN rid;
END; $$;

CREATE OR REPLACE FUNCTION public.approve_lab_result(_lab_result_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE uid UUID:=auth.uid(); r public.lab_results%ROWTYPE; o public.lab_orders%ROWTYPE;
BEGIN
 IF uid IS NULL OR NOT(public.has_role(uid,'admin') OR public.has_role(uid,'lab_technician') OR public.has_role(uid,'practitioner')) THEN RAISE EXCEPTION 'Laboratory approval role required'; END IF;
 SELECT * INTO r FROM public.lab_results WHERE id=_lab_result_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Laboratory result not found'; END IF;
 IF r.status<>'completed' THEN RAISE EXCEPTION 'Only completed results can be approved'; END IF;
 SELECT * INTO o FROM public.lab_orders WHERE id=r.lab_order_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Laboratory order not found'; END IF;
 IF o.status<>'completed' THEN RAISE EXCEPTION 'Laboratory order must be completed before result approval'; END IF;
 UPDATE public.lab_results SET status='approved',approved_by=uid,approved_at=now(),updated_at=now() WHERE id=r.id AND status='completed';
 UPDATE public.lab_orders SET status='approved',updated_at=now() WHERE id=o.id AND status='completed';
 RETURN jsonb_build_object('lab_result_id',r.id,'lab_order_id',o.id,'status','approved');
END; $$;

REVOKE ALL ON FUNCTION public.collect_lab_sample(UUID) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.enter_lab_result(UUID,TEXT,NUMERIC,TEXT,BOOLEAN) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.approve_lab_result(UUID) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.collect_lab_sample(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.enter_lab_result(UUID,TEXT,NUMERIC,TEXT,BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.approve_lab_result(UUID) TO authenticated;
