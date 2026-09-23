-- Strengthen pharmacy patient context and fertility cycle concurrency.
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
  IF NOT EXISTS(SELECT 1 FROM public.patients WHERE id=p.patient_id AND COALESCE(status,'active')<>'inactive') THEN RAISE EXCEPTION 'Prescription patient is not found or inactive'; END IF;
  IF p.status NOT IN('pending','paid') THEN RAISE EXCEPTION 'Prescription is not available for dispensing preparation'; END IF;
  IF p.computed_quantity IS NOT NULL AND _quantity>p.computed_quantity THEN RAISE EXCEPTION 'Dispensing quantity exceeds prescribed quantity'; END IF;
  IF p.encounter_id IS NOT NULL THEN
    SELECT status INTO encounter_status FROM public.encounters WHERE id=p.encounter_id;
    IF NOT FOUND OR encounter_status IN('completed','cancelled') THEN RAISE EXCEPTION 'Prescription is linked to a closed or missing encounter'; END IF;
  END IF;
  SELECT * INTO i FROM public.pharmacy_inventory WHERE id=_inventory_id FOR UPDATE;
  IF NOT FOUND OR NOT i.active THEN RAISE EXCEPTION 'Inventory item not found or inactive'; END IF;
  IF i.stock_quantity<_quantity THEN RAISE EXCEPTION 'Insufficient stock'; END IF;
  SELECT * INTO existing FROM public.pharmacy_dispensing_plans
    WHERE prescription_id=p.id AND status='unpaid' ORDER BY created_at DESC LIMIT 1 FOR UPDATE;
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

CREATE OR REPLACE FUNCTION public.confirm_pharmacy_dispense(_plan_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE p public.pharmacy_dispensing_plans;i public.pharmacy_inventory;r public.prescriptions;so public.service_orders;encounter_status text;uid uuid:=auth.uid();
BEGIN
 IF uid IS NULL OR NOT(public.has_role(uid,'admin') OR public.has_role(uid,'pharmacist')) THEN RAISE EXCEPTION 'Pharmacy role required'; END IF;
 SELECT * INTO p FROM public.pharmacy_dispensing_plans WHERE id=_plan_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Dispensing plan not found'; END IF;
 IF p.status<>'unpaid' THEN RAISE EXCEPTION 'Dispensing plan is already processed'; END IF;
 SELECT * INTO r FROM public.prescriptions WHERE id=p.prescription_id FOR UPDATE;
 IF NOT FOUND OR r.patient_id<>p.patient_id THEN RAISE EXCEPTION 'Prescription does not match dispensing patient'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.patients WHERE id=r.patient_id AND COALESCE(status,'active')<>'inactive') THEN RAISE EXCEPTION 'Prescription patient is not found or inactive'; END IF;
 IF r.status NOT IN('pending','paid') THEN RAISE EXCEPTION 'Prescription is not available for dispensing'; END IF;
 IF r.computed_quantity IS NOT NULL AND p.prepared_quantity>r.computed_quantity THEN RAISE EXCEPTION 'Dispensing quantity exceeds prescribed quantity'; END IF;
 IF r.encounter_id IS NOT NULL THEN
   SELECT status INTO encounter_status FROM public.encounters WHERE id=r.encounter_id;
   IF NOT FOUND OR encounter_status IN('completed','cancelled') THEN RAISE EXCEPTION 'Cannot dispense against a closed encounter'; END IF;
 END IF;
 SELECT * INTO so FROM public.service_orders WHERE id=p.service_order_id FOR UPDATE;
 IF NOT FOUND OR so.patient_id<>p.patient_id OR so.related_entity_id<>p.prescription_id THEN RAISE EXCEPTION 'Dispensing service order does not match prescription'; END IF;
 IF so.status NOT IN('released','in_progress') THEN RAISE EXCEPTION 'Payment has not been received or the pharmacy order has not been released'; END IF;
 SELECT * INTO i FROM public.pharmacy_inventory WHERE id=p.inventory_id FOR UPDATE;
 IF NOT FOUND OR NOT i.active THEN RAISE EXCEPTION 'Inventory item is unavailable'; END IF;
 IF i.stock_quantity<p.prepared_quantity THEN RAISE EXCEPTION 'Insufficient stock at dispensing time'; END IF;
 UPDATE public.pharmacy_inventory SET stock_quantity=stock_quantity-p.prepared_quantity,updated_at=now() WHERE id=i.id;
 UPDATE public.pharmacy_dispensing_plans SET status='dispensed',dispensed_by=uid,dispensed_at=now(),updated_at=now() WHERE id=p.id;
 UPDATE public.prescriptions SET status='dispensed',dispensed_by=uid,dispensed_at=now(),updated_at=now() WHERE id=r.id AND status IN('pending','paid');
 UPDATE public.service_orders SET status='completed',completed_at=COALESCE(completed_at,now()),updated_at=now() WHERE id=so.id AND status IN('released','in_progress');
 RETURN jsonb_build_object('plan_id',p.id,'status','dispensed','dispensed_by',uid);
END; $$;

CREATE OR REPLACE FUNCTION public.create_pharmacy_pos_sale(_patient_id uuid,_inventory_id uuid,_quantity integer)
RETURNS public.pharmacy_pos_sales LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE result public.pharmacy_pos_sales; item public.pharmacy_inventory; order_id uuid; patient_uuid uuid; uid uuid:=auth.uid();
BEGIN
 IF uid IS NULL OR NOT(public.has_role(uid,'admin') OR public.has_role(uid,'pharmacist') OR public.has_role(uid,'front_desk')) THEN RAISE EXCEPTION 'Pharmacy or front desk role required'; END IF;
 IF _quantity IS NULL OR _quantity<=0 THEN RAISE EXCEPTION 'Quantity must be greater than zero'; END IF;
 IF _patient_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.patients WHERE id=_patient_id AND COALESCE(status,'active')<>'inactive') THEN RAISE EXCEPTION 'Patient not found or inactive'; END IF;
 SELECT * INTO item FROM public.pharmacy_inventory WHERE id=_inventory_id FOR UPDATE;
 IF NOT FOUND OR NOT item.active OR item.stock_quantity<_quantity THEN RAISE EXCEPTION 'Insufficient or unavailable stock'; END IF;
 patient_uuid:=_patient_id;
 IF patient_uuid IS NULL THEN
   INSERT INTO public.patients(patient_code,first_name,last_name,status,created_by) VALUES(NULL,'Walk-in','Pharmacy','active',uid) RETURNING id INTO patient_uuid;
 END IF;
 INSERT INTO public.pharmacy_pos_sales(patient_id,medication,inventory_id,quantity,unit_price,created_by) VALUES(patient_uuid,item.drug_name,item.id,_quantity,COALESCE(item.unit_price,0),uid) RETURNING * INTO result;
 INSERT INTO public.service_orders(patient_id,department,service_name,amount,related_entity_id,status,requested_by,order_type,service_code,notes) VALUES(patient_uuid,'pharmacy','Walk-in: '||item.drug_name,COALESCE(item.unit_price,0)*_quantity,result.id,'pending_payment_approval',uid,'drug',item.id,'POS sale '||result.id::text) RETURNING id INTO order_id;
 UPDATE public.pharmacy_pos_sales SET service_order_id=order_id WHERE id=result.id RETURNING * INTO result;
 RETURN result;
END; $$;

CREATE OR REPLACE FUNCTION public.create_fertility_cycle_workflow(_patient_id UUID,_partner_name TEXT DEFAULT NULL,_cycle_type TEXT DEFAULT 'IVF',_start_date DATE DEFAULT CURRENT_DATE,_protocol TEXT DEFAULT NULL)
RETURNS public.fertility_cycles LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_cycle public.fertility_cycles; v_cycle_number integer; uid uuid:=auth.uid();
BEGIN
 IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 IF NOT (public.has_role(uid,'admin') OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse') OR public.has_role(uid,'midwife') OR public.has_role(uid,'specialist_nurse')) THEN RAISE EXCEPTION 'Insufficient role for fertility workflow'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.patients WHERE id=_patient_id AND COALESCE(status,'active')<>'inactive') THEN RAISE EXCEPTION 'Patient not found or inactive'; END IF;
 IF upper(trim(_cycle_type)) NOT IN('IVF','IUI','ICSI','FET') THEN RAISE EXCEPTION 'Unsupported fertility cycle type'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('fertility-cycle-number:'||_patient_id::text,0));
 SELECT COALESCE(MAX(cycle_number),0)+1 INTO v_cycle_number FROM public.fertility_cycles WHERE patient_id=_patient_id;
 INSERT INTO public.fertility_cycles(patient_id,partner_name,cycle_type,cycle_number,start_date,protocol,status,assigned_specialist)
 VALUES(_patient_id,NULLIF(trim(_partner_name),''),upper(trim(_cycle_type)),v_cycle_number,_start_date,NULLIF(trim(_protocol),''),'active',uid)
 RETURNING * INTO v_cycle;
 PERFORM public.record_system_audit('fertility_cycle_created','fertility','fertility_cycle',v_cycle.id,'info',jsonb_build_object('patient_id',_patient_id,'cycle_type',v_cycle.cycle_type));
 RETURN v_cycle;
END; $$;

REVOKE ALL ON FUNCTION public.prepare_pharmacy_dispensing(uuid,uuid,integer,text) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.confirm_pharmacy_dispense(uuid) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.create_pharmacy_pos_sale(uuid,uuid,integer) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.create_fertility_cycle_workflow(UUID,TEXT,TEXT,DATE,TEXT) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.prepare_pharmacy_dispensing(uuid,uuid,integer,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.confirm_pharmacy_dispense(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_pharmacy_pos_sale(uuid,uuid,integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_fertility_cycle_workflow(UUID,TEXT,TEXT,DATE,TEXT) TO authenticated;
