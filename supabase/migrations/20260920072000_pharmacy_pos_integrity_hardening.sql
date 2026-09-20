-- Harden pharmacy POS sale identity and stock lifecycle.
CREATE OR REPLACE FUNCTION public.create_pharmacy_pos_sale(_patient_id UUID,_inventory_id UUID,_quantity INTEGER)
RETURNS public.pharmacy_pos_sales LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE result public.pharmacy_pos_sales; item public.pharmacy_inventory; order_id UUID; patient_uuid UUID; uid UUID:=auth.uid();
BEGIN
  IF uid IS NULL OR NOT(public.has_role(uid,'admin') OR public.has_role(uid,'pharmacist') OR public.has_role(uid,'front_desk')) THEN RAISE EXCEPTION 'Pharmacy or front desk role required'; END IF;
  IF _quantity IS NULL OR _quantity<=0 THEN RAISE EXCEPTION 'Quantity must be greater than zero'; END IF;
  IF _patient_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.patients WHERE id=_patient_id) THEN RAISE EXCEPTION 'Patient not found'; END IF;
  SELECT * INTO item FROM public.pharmacy_inventory WHERE id=_inventory_id FOR UPDATE;
  IF NOT FOUND OR NOT item.active OR item.stock_quantity<_quantity THEN RAISE EXCEPTION 'Insufficient or unavailable stock'; END IF;
  patient_uuid:=_patient_id;
  IF patient_uuid IS NULL THEN
    INSERT INTO public.patients(patient_code,first_name,last_name,status,created_by)
    VALUES(NULL,'Walk-in','Pharmacy','active',uid) RETURNING id INTO patient_uuid;
  END IF;
  INSERT INTO public.pharmacy_pos_sales(patient_id,medication,inventory_id,quantity,unit_price,created_by)
  VALUES(patient_uuid,item.drug_name,item.id,_quantity,COALESCE(item.unit_price,0),uid) RETURNING * INTO result;
  INSERT INTO public.service_orders(patient_id,department,service_name,amount,related_entity_id,status,requested_by,order_type,service_code,notes)
  VALUES(patient_uuid,'pharmacy','Walk-in: '||item.drug_name,COALESCE(item.unit_price,0)*_quantity,result.id,'pending_payment_approval',uid,'drug',item.id,'POS sale '||result.id::text) RETURNING id INTO order_id;
  UPDATE public.pharmacy_pos_sales SET service_order_id=order_id WHERE id=result.id RETURNING * INTO result;
  RETURN result;
END; $$;

CREATE OR REPLACE FUNCTION public.confirm_pharmacy_pos_sale(_sale_id UUID)
RETURNS public.pharmacy_pos_sales LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE result public.pharmacy_pos_sales; item public.pharmacy_inventory; order_status TEXT; uid UUID:=auth.uid();
BEGIN
  IF uid IS NULL OR NOT(public.has_role(uid,'admin') OR public.has_role(uid,'pharmacist')) THEN RAISE EXCEPTION 'Pharmacist role required'; END IF;
  SELECT * INTO result FROM public.pharmacy_pos_sales WHERE id=_sale_id FOR UPDATE;
  IF NOT FOUND OR result.status<>'awaiting_payment' THEN RAISE EXCEPTION 'POS sale is not awaiting payment'; END IF;
  SELECT status INTO order_status FROM public.service_orders WHERE id=result.service_order_id FOR UPDATE;
  IF result.service_order_id IS NULL OR order_status NOT IN('released','in_progress') THEN RAISE EXCEPTION 'Payment has not been received or the order is not released'; END IF;
  SELECT * INTO item FROM public.pharmacy_inventory WHERE id=result.inventory_id FOR UPDATE;
  IF NOT FOUND OR NOT item.active OR item.stock_quantity<result.quantity THEN RAISE EXCEPTION 'Insufficient or unavailable stock at dispensing time'; END IF;
  UPDATE public.pharmacy_inventory SET stock_quantity=stock_quantity-result.quantity,updated_at=now() WHERE id=item.id;
  UPDATE public.pharmacy_pos_sales SET status='dispensed',dispensed_by=uid,dispensed_at=now() WHERE id=result.id RETURNING * INTO result;
  UPDATE public.service_orders SET status='completed',completed_at=COALESCE(completed_at,now()),updated_at=now() WHERE id=result.service_order_id AND status IN('released','in_progress');
  RETURN result;
END; $$;

REVOKE ALL ON FUNCTION public.create_pharmacy_pos_sale(UUID,UUID,INTEGER) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.confirm_pharmacy_pos_sale(UUID) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.create_pharmacy_pos_sale(UUID,UUID,INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.confirm_pharmacy_pos_sale(UUID) TO authenticated;
