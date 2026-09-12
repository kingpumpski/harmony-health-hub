CREATE TABLE IF NOT EXISTS public.pharmacy_dispensing_plans (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  prescription_id UUID NOT NULL REFERENCES public.prescriptions(id) ON DELETE CASCADE,
  patient_id UUID NOT NULL REFERENCES public.patients(id) ON DELETE CASCADE,
  inventory_id UUID REFERENCES public.pharmacy_inventory(id) ON DELETE SET NULL,
  medication_name TEXT NOT NULL,
  prescribed_dose TEXT,
  prescribed_frequency TEXT,
  prescribed_duration TEXT,
  computed_quantity INTEGER,
  prepared_quantity INTEGER NOT NULL CHECK (prepared_quantity > 0),
  status TEXT NOT NULL DEFAULT 'unpaid' CHECK (status IN ('unpaid','paid','dispensed','cancelled')),
  prepared_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  prepared_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  service_order_id UUID REFERENCES public.service_orders(id) ON DELETE SET NULL,
  invoice_item_id UUID REFERENCES public.invoice_items(id) ON DELETE SET NULL,
  dispensed_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  dispensed_at TIMESTAMPTZ,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_pharmacy_plan_patient_status ON public.pharmacy_dispensing_plans(patient_id,status,created_at DESC);
ALTER TABLE public.pharmacy_dispensing_plans ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "pharmacy plan staff access" ON public.pharmacy_dispensing_plans;
CREATE POLICY "pharmacy plan staff access" ON public.pharmacy_dispensing_plans FOR ALL TO authenticated USING (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'pharmacist') OR public.has_role(auth.uid(),'accountant') OR public.has_role(auth.uid(),'front_desk')) WITH CHECK (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'pharmacist') OR public.has_role(auth.uid(),'accountant') OR public.has_role(auth.uid(),'front_desk'));
CREATE OR REPLACE FUNCTION public.prepare_pharmacy_dispensing(_prescription_id UUID,_inventory_id UUID,_quantity INTEGER,_notes TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE p public.prescriptions; i public.pharmacy_inventory; plan_id UUID; order_id UUID; price NUMERIC;
BEGIN
 IF NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'pharmacist')) THEN RAISE EXCEPTION 'Pharmacy role required'; END IF;
 SELECT * INTO p FROM public.prescriptions WHERE id=_prescription_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Prescription not found'; END IF;
 SELECT * INTO i FROM public.pharmacy_inventory WHERE id=_inventory_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'Inventory item not found'; END IF;
 IF _quantity IS NULL OR _quantity <= 0 THEN RAISE EXCEPTION 'Quantity must be greater than zero'; END IF;
 IF i.stock_quantity < _quantity THEN RAISE EXCEPTION 'Insufficient stock'; END IF;
 SELECT unit_price INTO price FROM public.pharmacy_inventory WHERE id=_inventory_id;
 INSERT INTO public.pharmacy_dispensing_plans(prescription_id,patient_id,inventory_id,medication_name,prescribed_dose,prescribed_frequency,prescribed_duration,computed_quantity,prepared_quantity,prepared_by,notes)
 VALUES(p.id,p.patient_id,i.id,i.drug_name,p.dosage,p.frequency,p.duration,p.computed_quantity,_quantity,auth.uid(),_notes) RETURNING id INTO plan_id;
 INSERT INTO public.service_orders(patient_id,department,service_name,amount,related_entity_id,status,requested_by,order_type,service_code,notes)
 VALUES(p.patient_id,'pharmacy','Dispense: '||i.drug_name,price*_quantity,p.id,'pending_payment_approval',auth.uid(),'drug',i.id,'Pharmacy preparation '||plan_id::text) RETURNING id INTO order_id;
 UPDATE public.pharmacy_dispensing_plans SET service_order_id=order_id WHERE id=plan_id;
 RETURN jsonb_build_object('plan_id',plan_id,'service_order_id',order_id,'amount',price*_quantity,'status','unpaid');
END; $$;
CREATE OR REPLACE FUNCTION public.confirm_pharmacy_dispense(_plan_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE p public.pharmacy_dispensing_plans; i public.pharmacy_inventory;
BEGIN
 IF NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'pharmacist')) THEN RAISE EXCEPTION 'Pharmacy role required'; END IF;
 SELECT * INTO p FROM public.pharmacy_dispensing_plans WHERE id=_plan_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Dispensing plan not found'; END IF;
 IF p.status <> 'unpaid' THEN RAISE EXCEPTION 'Dispensing plan is already processed'; END IF;
 IF p.service_order_id IS NULL OR NOT EXISTS(SELECT 1 FROM public.service_orders WHERE id=p.service_order_id AND status IN ('released','in_progress')) THEN RAISE EXCEPTION 'Payment has not been received or the pharmacy order has not been released'; END IF;
 SELECT * INTO i FROM public.pharmacy_inventory WHERE id=p.inventory_id FOR UPDATE;
 IF i.stock_quantity < p.prepared_quantity THEN RAISE EXCEPTION 'Insufficient stock at dispensing time'; END IF;
 UPDATE public.pharmacy_inventory SET stock_quantity=stock_quantity-p.prepared_quantity WHERE id=i.id;
 UPDATE public.pharmacy_dispensing_plans SET status='dispensed',dispensed_by=auth.uid(),dispensed_at=now(),updated_at=now() WHERE id=p.id;
 UPDATE public.prescriptions SET status='dispensed',dispensed_by=auth.uid(),dispensed_at=now() WHERE id=p.prescription_id AND status='pending';
 PERFORM public.record_system_audit('pharmacy_dispensed','pharmacy','pharmacy_dispensing_plans',p.id,'info',jsonb_build_object('patient_id',p.patient_id,'prescription_id',p.prescription_id,'quantity',p.prepared_quantity,'dispensed_by',auth.uid(),'dispensed_at',now()));
 RETURN jsonb_build_object('plan_id',p.id,'status','dispensed','dispensed_by',auth.uid());
END; $$;
REVOKE ALL ON FUNCTION public.prepare_pharmacy_dispensing(UUID,UUID,INTEGER,TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.confirm_pharmacy_dispense(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.prepare_pharmacy_dispensing(UUID,UUID,INTEGER,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.confirm_pharmacy_dispense(UUID) TO authenticated;
