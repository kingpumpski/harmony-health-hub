CREATE OR REPLACE FUNCTION public.create_walk_in_billable_service(_patient_id UUID,_service_code TEXT,_quantity NUMERIC DEFAULT 1,_notes TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE t public.service_tariffs%ROWTYPE; so UUID;
BEGIN
 IF NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'accountant') OR public.has_role(auth.uid(),'front_desk')) THEN RAISE EXCEPTION 'Billing access denied'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.patients WHERE id=_patient_id) THEN RAISE EXCEPTION 'Patient not found'; END IF;
 IF _quantity IS NULL OR _quantity<=0 THEN RAISE EXCEPTION 'Quantity must be greater than zero'; END IF;
 SELECT * INTO t FROM public.service_tariffs WHERE service_code=_service_code AND active;
 IF NOT FOUND THEN RAISE EXCEPTION 'Active service tariff not found'; END IF;
 INSERT INTO public.service_orders(patient_id,department,service_name,amount,quantity,unit_price,status,requested_by,created_by,order_type,service_code,payment_required)
 VALUES(_patient_id,t.department,t.service_name,t.amount*_quantity,_quantity,t.amount,'pending_payment_approval',auth.uid(),auth.uid(),'walk_in',t.service_code,true)
 RETURNING id INTO so;
 RETURN jsonb_build_object('service_order_id',so,'amount',t.amount*_quantity,'status','pending_payment_approval');
END; $$;
REVOKE ALL ON FUNCTION public.create_walk_in_billable_service(UUID,TEXT,NUMERIC,TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_walk_in_billable_service(UUID,TEXT,NUMERIC,TEXT) TO authenticated;
