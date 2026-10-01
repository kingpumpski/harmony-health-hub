-- Harden pharmacy POS facility lineage.
BEGIN;

CREATE OR REPLACE FUNCTION public.create_pharmacy_pos_sale(_patient_id uuid,_inventory_id uuid,_quantity integer)
RETURNS public.pharmacy_pos_sales LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE result public.pharmacy_pos_sales; item public.pharmacy_inventory; order_id uuid; patient_uuid uuid; uid uuid:=auth.uid();pf uuid;
BEGIN
 IF uid IS NULL OR NOT(public.has_role(uid,'admin') OR public.has_role(uid,'it_admin') OR public.has_role(uid,'pharmacist') OR public.has_role(uid,'front_desk')) THEN RAISE EXCEPTION 'Pharmacy or front desk role required'; END IF;
 IF _quantity IS NULL OR _quantity<=0 THEN RAISE EXCEPTION 'Quantity must be greater than zero'; END IF;
 SELECT * INTO item FROM public.pharmacy_inventory WHERE id=_inventory_id FOR UPDATE;
 IF NOT FOUND OR NOT item.active OR item.stock_quantity<_quantity THEN RAISE EXCEPTION 'Insufficient or unavailable stock'; END IF;
 IF _patient_id IS NOT NULL THEN pf:=public.assert_patient_facility_context(_patient_id); patient_uuid:=_patient_id;
 ELSE
   pf:=public.current_user_facility_id();
   IF pf IS NULL AND NOT(public.has_role(uid,'admin') OR public.has_role(uid,'it_admin')) THEN RAISE EXCEPTION 'Active facility context is required for a walk-in sale'; END IF;
   INSERT INTO public.patients(patient_code,first_name,last_name,status,created_by,facility_id) VALUES(NULL,'Walk-in','Pharmacy','active',uid,pf) RETURNING id INTO patient_uuid;
 END IF;
 INSERT INTO public.pharmacy_pos_sales(patient_id,medication,inventory_id,quantity,unit_price,created_by,facility_id)
 VALUES(patient_uuid,item.drug_name,item.id,_quantity,COALESCE(item.unit_price,0),uid,pf) RETURNING * INTO result;
 INSERT INTO public.service_orders(patient_id,department,service_name,amount,related_entity_id,status,requested_by,order_type,service_code,notes,facility_id)
 VALUES(patient_uuid,'pharmacy','Walk-in: '||item.drug_name,COALESCE(item.unit_price,0)*_quantity,result.id,'pending_payment_approval',uid,'drug',item.id,'POS sale '||result.id::text,pf) RETURNING id INTO order_id;
 UPDATE public.pharmacy_pos_sales SET service_order_id=order_id WHERE id=result.id RETURNING * INTO result;
 RETURN result;
END; $$;

CREATE OR REPLACE FUNCTION public.confirm_pharmacy_pos_sale(_sale_id uuid)
RETURNS public.pharmacy_pos_sales LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE result public.pharmacy_pos_sales; item public.pharmacy_inventory; so public.service_orders; uid uuid:=auth.uid();pf uuid;
BEGIN
 IF uid IS NULL OR NOT(public.has_role(uid,'admin') OR public.has_role(uid,'it_admin') OR public.has_role(uid,'pharmacist')) THEN RAISE EXCEPTION 'Pharmacist role required'; END IF;
 SELECT * INTO result FROM public.pharmacy_pos_sales WHERE id=_sale_id FOR UPDATE; IF NOT FOUND OR result.status<>'awaiting_payment' THEN RAISE EXCEPTION 'POS sale is not awaiting payment'; END IF;
 pf:=public.assert_patient_facility_context(result.patient_id);
 IF result.facility_id IS NULL OR result.facility_id IS DISTINCT FROM pf THEN RAISE EXCEPTION 'POS sale facility attribution is unresolved or mismatched'; END IF;
 SELECT * INTO so FROM public.service_orders WHERE id=result.service_order_id FOR UPDATE;
 IF NOT FOUND OR so.patient_id<>result.patient_id OR so.related_entity_id<>result.id OR so.facility_id IS DISTINCT FROM pf THEN RAISE EXCEPTION 'POS service order facility linkage is invalid'; END IF;
 IF so.status NOT IN('released','in_progress') THEN RAISE EXCEPTION 'Payment has not been received or the order is not released'; END IF;
 SELECT * INTO item FROM public.pharmacy_inventory WHERE id=result.inventory_id FOR UPDATE;
 IF NOT FOUND OR NOT item.active OR item.stock_quantity<result.quantity THEN RAISE EXCEPTION 'Insufficient or unavailable stock at dispensing time'; END IF;
 UPDATE public.pharmacy_inventory SET stock_quantity=stock_quantity-result.quantity,updated_at=pg_catalog.now() WHERE id=item.id;
 UPDATE public.pharmacy_pos_sales SET status='dispensed',dispensed_by=uid,dispensed_at=pg_catalog.now() WHERE id=result.id RETURNING * INTO result;
 UPDATE public.service_orders SET status='completed',completed_at=COALESCE(completed_at,pg_catalog.now()),updated_at=pg_catalog.now() WHERE id=result.service_order_id AND status IN('released','in_progress');
 RETURN result;
END; $$;

REVOKE ALL ON FUNCTION public.create_pharmacy_pos_sale(uuid,uuid,integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.create_pharmacy_pos_sale(uuid,uuid,integer) TO authenticated;
REVOKE ALL ON FUNCTION public.confirm_pharmacy_pos_sale(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.confirm_pharmacy_pos_sale(uuid) TO authenticated;

COMMIT;