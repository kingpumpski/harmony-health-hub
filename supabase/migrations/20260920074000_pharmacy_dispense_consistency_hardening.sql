-- Harden prescription dispensing consistency and replay boundaries.
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
REVOKE ALL ON FUNCTION public.confirm_pharmacy_dispense(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.confirm_pharmacy_dispense(uuid) TO authenticated;
