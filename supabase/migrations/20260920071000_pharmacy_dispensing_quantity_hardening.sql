-- Pharmacy workflow hardening: enforce dispensing quantity against prescription and restrict inventory search.
CREATE OR REPLACE FUNCTION public.find_pharmacy_alternatives(_medication text,_strength text DEFAULT NULL)
RETURNS TABLE(id uuid,drug_name text,brand_name text,generic_name text,strength text,form text,supplier text,stock_quantity integer,unit_price numeric)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT(public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'pharmacist')) THEN
    RAISE EXCEPTION 'Pharmacy role required';
  END IF;
  RETURN QUERY
  SELECT i.id,i.drug_name,i.brand_name,i.generic_name,i.strength,i.form,i.supplier,i.stock_quantity,i.unit_price
  FROM public.pharmacy_inventory i
  WHERE i.active AND i.stock_quantity>0
    AND (i.drug_name ILIKE '%'||COALESCE(_medication,'')||'%' OR i.generic_name ILIKE '%'||COALESCE(_medication,'')||'%' OR i.brand_name ILIKE '%'||COALESCE(_medication,'')||'%')
    AND (_strength IS NULL OR i.strength ILIKE '%'||_strength||'%')
  ORDER BY CASE WHEN lower(i.drug_name)=lower(_medication) THEN 0 ELSE 1 END,i.stock_quantity DESC,i.drug_name
  LIMIT 20;
END; $$;

CREATE OR REPLACE FUNCTION public.prepare_pharmacy_dispensing(_prescription_id uuid,_inventory_id uuid,_quantity integer,_notes text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  p public.prescriptions;
  i public.pharmacy_inventory;
  existing public.pharmacy_dispensing_plans;
  plan_id uuid;
  order_id uuid;
  price numeric;
  encounter_status text;
  uid uuid := auth.uid();
BEGIN
  IF uid IS NULL OR NOT(public.has_role(uid,'admin') OR public.has_role(uid,'pharmacist')) THEN RAISE EXCEPTION 'Pharmacy role required'; END IF;
  IF _quantity IS NULL OR _quantity<=0 THEN RAISE EXCEPTION 'Quantity must be greater than zero'; END IF;

  SELECT * INTO p FROM public.prescriptions WHERE id=_prescription_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Prescription not found'; END IF;
  IF p.status NOT IN('pending','paid') THEN RAISE EXCEPTION 'Prescription is not available for dispensing preparation'; END IF;
  IF p.computed_quantity IS NOT NULL AND _quantity>p.computed_quantity THEN
    RAISE EXCEPTION 'Dispensing quantity exceeds prescribed quantity';
  END IF;
  IF p.encounter_id IS NOT NULL THEN
    SELECT status INTO encounter_status FROM public.encounters WHERE id=p.encounter_id;
    IF NOT FOUND OR encounter_status IN('completed','cancelled') THEN RAISE EXCEPTION 'Prescription is linked to a closed or missing encounter'; END IF;
  END IF;

  SELECT * INTO i FROM public.pharmacy_inventory WHERE id=_inventory_id FOR UPDATE;
  IF NOT FOUND OR NOT i.active THEN RAISE EXCEPTION 'Inventory item not found or inactive'; END IF;
  IF i.stock_quantity<_quantity THEN RAISE EXCEPTION 'Insufficient stock'; END IF;

  SELECT * INTO existing
  FROM public.pharmacy_dispensing_plans
  WHERE prescription_id=p.id AND status='unpaid'
  ORDER BY created_at DESC LIMIT 1
  FOR UPDATE;
  IF FOUND THEN
    RETURN jsonb_build_object('plan_id',existing.id,'service_order_id',existing.service_order_id,'amount',
      (SELECT amount FROM public.service_orders WHERE id=existing.service_order_id),'status','unpaid','existing',true);
  END IF;

  price:=COALESCE(i.unit_price,0);
  INSERT INTO public.pharmacy_dispensing_plans(prescription_id,patient_id,inventory_id,medication_name,prescribed_dose,prescribed_frequency,prescribed_duration,computed_quantity,prepared_quantity,prepared_by,notes)
  VALUES(p.id,p.patient_id,i.id,i.drug_name,p.dosage,p.frequency,p.duration,p.computed_quantity,_quantity,uid,_notes)
  RETURNING id INTO plan_id;

  INSERT INTO public.service_orders(patient_id,department,service_name,amount,related_entity_id,status,requested_by,order_type,service_code,notes)
  VALUES(p.patient_id,'pharmacy','Dispense: '||i.drug_name,price*_quantity,p.id,'pending_payment_approval',uid,'drug',i.id,'Pharmacy preparation '||plan_id::text)
  RETURNING id INTO order_id;

  UPDATE public.pharmacy_dispensing_plans SET service_order_id=order_id,updated_at=now() WHERE id=plan_id;
  RETURN jsonb_build_object('plan_id',plan_id,'service_order_id',order_id,'amount',price*_quantity,'status','unpaid');
END; $$;

REVOKE ALL ON FUNCTION public.find_pharmacy_alternatives(text,text) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.prepare_pharmacy_dispensing(uuid,uuid,integer,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.find_pharmacy_alternatives(text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.prepare_pharmacy_dispensing(uuid,uuid,integer,text) TO authenticated;
