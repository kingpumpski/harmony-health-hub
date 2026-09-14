-- Server-authoritative pharmacy dispensing/POS lifecycle.
-- Preparation creates a payment-gated service order; stock is committed only at confirmed dispensing.

CREATE OR REPLACE FUNCTION public.find_pharmacy_alternatives(_medication text,_strength text DEFAULT NULL)
RETURNS TABLE(id uuid,drug_name text,brand_name text,generic_name text,strength text,form text,supplier text,stock_quantity integer,unit_price numeric)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
  SELECT i.id,i.drug_name,i.brand_name,i.generic_name,i.strength,i.form,i.supplier,i.stock_quantity,i.unit_price
  FROM public.pharmacy_inventory i
  WHERE i.active AND i.stock_quantity>0
    AND (i.drug_name ILIKE '%'||COALESCE(_medication,'')||'%' OR i.generic_name ILIKE '%'||COALESCE(_medication,'')||'%' OR i.brand_name ILIKE '%'||COALESCE(_medication,'')||'%')
    AND (_strength IS NULL OR i.strength ILIKE '%'||_strength||'%')
  ORDER BY CASE WHEN lower(i.drug_name)=lower(_medication) THEN 0 ELSE 1 END,i.stock_quantity DESC,i.drug_name
  LIMIT 20;
$$;

CREATE OR REPLACE FUNCTION public.prepare_pharmacy_dispensing(_prescription_id uuid,_inventory_id uuid,_quantity integer,_notes text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE p public.prescriptions;i public.pharmacy_inventory;plan_id uuid;order_id uuid;price numeric;encounter_status text;
BEGIN
 IF auth.uid() IS NULL OR NOT(public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'pharmacist')) THEN RAISE EXCEPTION 'Pharmacy role required'; END IF;
 SELECT * INTO p FROM public.prescriptions WHERE id=_prescription_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Prescription not found'; END IF;
 IF p.status NOT IN('pending','paid') THEN RAISE EXCEPTION 'Prescription is not available for dispensing preparation'; END IF;
 IF p.encounter_id IS NOT NULL THEN SELECT status INTO encounter_status FROM public.encounters WHERE id=p.encounter_id; IF NOT FOUND OR encounter_status IN('completed','cancelled') THEN RAISE EXCEPTION 'Prescription is linked to a closed or missing encounter'; END IF; END IF;
 SELECT * INTO i FROM public.pharmacy_inventory WHERE id=_inventory_id FOR UPDATE;
 IF NOT FOUND OR NOT i.active THEN RAISE EXCEPTION 'Inventory item not found or inactive'; END IF;
 IF _quantity IS NULL OR _quantity<=0 THEN RAISE EXCEPTION 'Quantity must be greater than zero'; END IF;
 IF i.stock_quantity<_quantity THEN RAISE EXCEPTION 'Insufficient stock'; END IF;
 price:=COALESCE(i.unit_price,0);
 INSERT INTO public.pharmacy_dispensing_plans(prescription_id,patient_id,inventory_id,medication_name,prescribed_dose,prescribed_frequency,prescribed_duration,computed_quantity,prepared_quantity,prepared_by,notes)
 VALUES(p.id,p.patient_id,i.id,i.drug_name,p.dosage,p.frequency,p.duration,p.computed_quantity,_quantity,auth.uid(),_notes) RETURNING id INTO plan_id;
 INSERT INTO public.service_orders(patient_id,department,service_name,amount,related_entity_id,status,requested_by,order_type,service_code,notes)
 VALUES(p.patient_id,'pharmacy','Dispense: '||i.drug_name,price*_quantity,p.id,'pending_payment_approval',auth.uid(),'drug',i.id,'Pharmacy preparation '||plan_id::text) RETURNING id INTO order_id;
 UPDATE public.pharmacy_dispensing_plans SET service_order_id=order_id,updated_at=now() WHERE id=plan_id;
 RETURN jsonb_build_object('plan_id',plan_id,'service_order_id',order_id,'amount',price*_quantity,'status','unpaid');
END; $$;

CREATE OR REPLACE FUNCTION public.confirm_pharmacy_dispense(_plan_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE p public.pharmacy_dispensing_plans;i public.pharmacy_inventory;order_status text;encounter_status text;
BEGIN
 IF auth.uid() IS NULL OR NOT(public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'pharmacist')) THEN RAISE EXCEPTION 'Pharmacy role required'; END IF;
 SELECT * INTO p FROM public.pharmacy_dispensing_plans WHERE id=_plan_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Dispensing plan not found'; END IF;
 IF p.status<>'unpaid' THEN RAISE EXCEPTION 'Dispensing plan is already processed'; END IF;
 SELECT status INTO order_status FROM public.service_orders WHERE id=p.service_order_id FOR UPDATE;
 IF order_status NOT IN('released','in_progress') THEN RAISE EXCEPTION 'Payment has not been received or the pharmacy order has not been released'; END IF;
 SELECT e.status INTO encounter_status FROM public.encounters e JOIN public.prescriptions r ON r.encounter_id=e.id WHERE r.id=p.prescription_id;
 IF encounter_status IN('completed','cancelled') THEN RAISE EXCEPTION 'Cannot dispense against a closed encounter'; END IF;
 SELECT * INTO i FROM public.pharmacy_inventory WHERE id=p.inventory_id FOR UPDATE;
 IF NOT FOUND OR NOT i.active THEN RAISE EXCEPTION 'Inventory item is unavailable'; END IF;
 IF i.stock_quantity<p.prepared_quantity THEN RAISE EXCEPTION 'Insufficient stock at dispensing time'; END IF;
 UPDATE public.pharmacy_inventory SET stock_quantity=stock_quantity-p.prepared_quantity,updated_at=now() WHERE id=i.id;
 UPDATE public.pharmacy_dispensing_plans SET status='dispensed',dispensed_by=auth.uid(),dispensed_at=now(),updated_at=now() WHERE id=p.id;
 UPDATE public.prescriptions SET status='dispensed',dispensed_by=auth.uid(),dispensed_at=now(),updated_at=now() WHERE id=p.prescription_id AND status IN('pending','paid');
 UPDATE public.service_orders SET status='completed',completed_at=COALESCE(completed_at,now()),updated_at=now() WHERE id=p.service_order_id AND status IN('released','in_progress');
 RETURN jsonb_build_object('plan_id',p.id,'status','dispensed','dispensed_by',auth.uid());
END; $$;

CREATE OR REPLACE FUNCTION public.create_pharmacy_pos_sale(_patient_id uuid,_inventory_id uuid,_quantity integer)
RETURNS public.pharmacy_pos_sales LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE result public.pharmacy_pos_sales;item public.pharmacy_inventory;order_id uuid;patient_uuid uuid;
BEGIN
 IF auth.uid() IS NULL OR NOT(public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'pharmacist') OR public.has_role(auth.uid(),'front_desk')) THEN RAISE EXCEPTION 'Pharmacy or front desk role required'; END IF;
 IF _quantity IS NULL OR _quantity<=0 THEN RAISE EXCEPTION 'Quantity must be greater than zero'; END IF;
 SELECT * INTO item FROM public.pharmacy_inventory WHERE id=_inventory_id FOR UPDATE;
 IF NOT FOUND OR NOT item.active OR item.stock_quantity<_quantity THEN RAISE EXCEPTION 'Insufficient or unavailable stock'; END IF;
 patient_uuid:=_patient_id;
 IF patient_uuid IS NULL THEN INSERT INTO public.patients(patient_code,first_name,last_name,status,created_by) VALUES(NULL,'Walk-in','Pharmacy','active',auth.uid()) RETURNING id INTO patient_uuid; END IF;
 INSERT INTO public.pharmacy_pos_sales(patient_id,medication,inventory_id,quantity,unit_price,created_by) VALUES(patient_uuid,item.drug_name,item.id,_quantity,COALESCE(item.unit_price,0),auth.uid()) RETURNING * INTO result;
 INSERT INTO public.service_orders(patient_id,department,service_name,amount,related_entity_id,status,requested_by,order_type,service_code,notes) VALUES(patient_uuid,'pharmacy','Walk-in: '||item.drug_name,COALESCE(item.unit_price,0)*_quantity,result.id,'pending_payment_approval',auth.uid(),'drug',item.id,'POS sale '||result.id::text) RETURNING id INTO order_id;
 UPDATE public.pharmacy_pos_sales SET service_order_id=order_id WHERE id=result.id RETURNING * INTO result;
 RETURN result;
END; $$;

CREATE OR REPLACE FUNCTION public.confirm_pharmacy_pos_sale(_sale_id uuid)
RETURNS public.pharmacy_pos_sales LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE result public.pharmacy_pos_sales;item public.pharmacy_inventory;order_status text;
BEGIN
 IF auth.uid() IS NULL OR NOT(public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'pharmacist')) THEN RAISE EXCEPTION 'Pharmacist role required'; END IF;
 SELECT * INTO result FROM public.pharmacy_pos_sales WHERE id=_sale_id FOR UPDATE;
 IF NOT FOUND OR result.status<>'awaiting_payment' THEN RAISE EXCEPTION 'POS sale is not awaiting payment'; END IF;
 SELECT status INTO order_status FROM public.service_orders WHERE id=result.service_order_id FOR UPDATE;
 IF order_status NOT IN('released','in_progress') THEN RAISE EXCEPTION 'Payment has not been received or the order is not released'; END IF;
 SELECT * INTO item FROM public.pharmacy_inventory WHERE id=result.inventory_id FOR UPDATE;
 IF NOT FOUND OR NOT item.active OR item.stock_quantity<result.quantity THEN RAISE EXCEPTION 'Insufficient stock at dispensing time'; END IF;
 UPDATE public.pharmacy_inventory SET stock_quantity=stock_quantity-result.quantity,updated_at=now() WHERE id=item.id;
 UPDATE public.pharmacy_pos_sales SET status='dispensed',dispensed_by=auth.uid(),dispensed_at=now() WHERE id=result.id RETURNING * INTO result;
 UPDATE public.service_orders SET status='completed',completed_at=COALESCE(completed_at,now()),updated_at=now() WHERE id=result.service_order_id AND status IN('released','in_progress');
 RETURN result;
END; $$;

REVOKE INSERT,UPDATE,DELETE ON TABLE public.pharmacy_dispensing_plans,public.pharmacy_pos_sales FROM authenticated;
REVOKE ALL ON FUNCTION public.find_pharmacy_alternatives(text,text) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.prepare_pharmacy_dispensing(uuid,uuid,integer,text) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.confirm_pharmacy_dispense(uuid) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.create_pharmacy_pos_sale(uuid,uuid,integer) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.confirm_pharmacy_pos_sale(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.find_pharmacy_alternatives(text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.prepare_pharmacy_dispensing(uuid,uuid,integer,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.confirm_pharmacy_dispense(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_pharmacy_pos_sale(uuid,uuid,integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.confirm_pharmacy_pos_sale(uuid) TO authenticated;
