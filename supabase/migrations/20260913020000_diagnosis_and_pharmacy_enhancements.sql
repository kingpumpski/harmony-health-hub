-- Coded diagnosis entry and pharmacy alternatives/POS contracts.

CREATE OR REPLACE FUNCTION public.add_encounter_diagnosis(
  _encounter_id UUID,
  _diagnosis TEXT,
  _icd_code TEXT DEFAULT NULL
)
RETURNS public.diagnoses
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE result public.diagnoses;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_clinical_staff(auth.uid()) THEN RAISE EXCEPTION 'Clinical staff role required'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.encounters WHERE id = _encounter_id) THEN RAISE EXCEPTION 'Encounter does not exist'; END IF;
  IF NULLIF(trim(_diagnosis), '') IS NULL THEN RAISE EXCEPTION 'Diagnosis is required'; END IF;
  IF _icd_code IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.icd_codes WHERE code = upper(trim(_icd_code))) THEN RAISE EXCEPTION 'Diagnosis code is not in the approved ICD-10/STG catalogue'; END IF;
  INSERT INTO public.diagnoses (encounter_id, diagnosis, icd_code, is_principal)
  VALUES (_encounter_id, trim(_diagnosis), NULLIF(upper(trim(_icd_code)), ''), false)
  RETURNING * INTO result;
  RETURN result;
END;
$$;
REVOKE ALL ON FUNCTION public.add_encounter_diagnosis(UUID,TEXT,TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.add_encounter_diagnosis(UUID,TEXT,TEXT) TO authenticated;

ALTER TABLE public.pharmacy_inventory
  ADD COLUMN IF NOT EXISTS brand_name TEXT,
  ADD COLUMN IF NOT EXISTS supplier TEXT,
  ADD COLUMN IF NOT EXISTS batch_number TEXT,
  ADD COLUMN IF NOT EXISTS received_at TIMESTAMPTZ;
CREATE INDEX IF NOT EXISTS idx_pharmacy_inventory_match ON public.pharmacy_inventory(generic_name, strength, stock_quantity);

CREATE OR REPLACE FUNCTION public.find_pharmacy_alternatives(_medication TEXT, _strength TEXT DEFAULT NULL)
RETURNS TABLE(id UUID, drug_name TEXT, brand_name TEXT, generic_name TEXT, strength TEXT, form TEXT, supplier TEXT, stock_quantity INTEGER, unit_price NUMERIC)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT i.id, i.drug_name, i.brand_name, i.generic_name, i.strength, i.form, i.supplier, i.stock_quantity, i.unit_price
  FROM public.pharmacy_inventory i
  WHERE i.stock_quantity > 0
    AND (i.drug_name ILIKE '%' || COALESCE(_medication,'') || '%' OR i.generic_name ILIKE '%' || COALESCE(_medication,'') || '%' OR i.brand_name ILIKE '%' || COALESCE(_medication,'') || '%')
    AND (_strength IS NULL OR i.strength ILIKE '%' || _strength || '%')
  ORDER BY CASE WHEN lower(i.drug_name) = lower(_medication) THEN 0 ELSE 1 END, i.stock_quantity DESC, i.drug_name
  LIMIT 20;
$$;
GRANT EXECUTE ON FUNCTION public.find_pharmacy_alternatives(TEXT,TEXT) TO authenticated;

CREATE TABLE IF NOT EXISTS public.pharmacy_pos_sales (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id UUID REFERENCES public.patients(id) ON DELETE SET NULL,
  medication TEXT NOT NULL,
  inventory_id UUID REFERENCES public.pharmacy_inventory(id) ON DELETE RESTRICT,
  quantity INTEGER NOT NULL CHECK (quantity > 0),
  unit_price NUMERIC(10,2) NOT NULL CHECK (unit_price >= 0),
  total_amount NUMERIC(12,2) GENERATED ALWAYS AS (quantity * unit_price) STORED,
  service_order_id UUID REFERENCES public.service_orders(id) ON DELETE SET NULL,
  status TEXT NOT NULL DEFAULT 'awaiting_payment' CHECK (status IN ('awaiting_payment','released','dispensed','cancelled')),
  created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  dispensed_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  dispensed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.pharmacy_pos_sales ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "pharmacy pos staff access" ON public.pharmacy_pos_sales;
CREATE POLICY "pharmacy pos staff access" ON public.pharmacy_pos_sales FOR ALL TO authenticated
  USING (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'pharmacist') OR public.has_role(auth.uid(),'front_desk') OR public.has_role(auth.uid(),'accountant'))
  WITH CHECK (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'pharmacist') OR public.has_role(auth.uid(),'front_desk') OR public.has_role(auth.uid(),'accountant'));

CREATE OR REPLACE FUNCTION public.create_pharmacy_pos_sale(_patient_id UUID, _inventory_id UUID, _quantity INTEGER)
RETURNS public.pharmacy_pos_sales LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE result public.pharmacy_pos_sales; item public.pharmacy_inventory; order_id UUID; patient_uuid UUID;
BEGIN
  IF NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'pharmacist') OR public.has_role(auth.uid(),'front_desk')) THEN RAISE EXCEPTION 'Pharmacy or front desk role required'; END IF;
  IF _quantity IS NULL OR _quantity <= 0 THEN RAISE EXCEPTION 'Quantity must be greater than zero'; END IF;
  SELECT * INTO item FROM public.pharmacy_inventory WHERE id = _inventory_id FOR UPDATE;
  IF NOT FOUND OR item.stock_quantity < _quantity THEN RAISE EXCEPTION 'Insufficient stock'; END IF;
  patient_uuid := _patient_id;
  IF patient_uuid IS NULL THEN
    INSERT INTO public.patients(patient_code,first_name,last_name,status,created_by)
    VALUES(NULL,'Walk-in','Pharmacy','active',auth.uid()) RETURNING id INTO patient_uuid;
  END IF;
  INSERT INTO public.pharmacy_pos_sales(patient_id,medication,inventory_id,quantity,unit_price,created_by)
  VALUES(patient_uuid,item.drug_name,item.id,_quantity,item.unit_price,auth.uid()) RETURNING * INTO result;
  INSERT INTO public.service_orders(patient_id,department,service_name,amount,related_entity_id,status,requested_by,order_type,service_code,notes)
  VALUES(patient_uuid,'pharmacy','Walk-in: ' || item.drug_name,item.unit_price*_quantity,result.id,'pending_payment_approval',auth.uid(),'drug',item.id,'POS sale ' || result.id::text) RETURNING id INTO order_id;
  UPDATE public.pharmacy_pos_sales SET service_order_id=order_id WHERE id=result.id RETURNING * INTO result;
  RETURN result;
END;
$$;
GRANT EXECUTE ON FUNCTION public.create_pharmacy_pos_sale(UUID,UUID,INTEGER) TO authenticated;

CREATE OR REPLACE FUNCTION public.confirm_pharmacy_pos_sale(_sale_id UUID)
RETURNS public.pharmacy_pos_sales LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE result public.pharmacy_pos_sales; item public.pharmacy_inventory;
BEGIN
  IF NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'pharmacist')) THEN RAISE EXCEPTION 'Pharmacist role required'; END IF;
  SELECT * INTO result FROM public.pharmacy_pos_sales WHERE id=_sale_id FOR UPDATE;
  IF NOT FOUND OR result.status <> 'awaiting_payment' THEN RAISE EXCEPTION 'POS sale is not awaiting payment'; END IF;
  IF result.service_order_id IS NULL OR NOT EXISTS (SELECT 1 FROM public.service_orders WHERE id=result.service_order_id AND status IN ('released','in_progress')) THEN RAISE EXCEPTION 'Payment has not been received or the order is not released'; END IF;
  SELECT * INTO item FROM public.pharmacy_inventory WHERE id=result.inventory_id FOR UPDATE;
  IF item.stock_quantity < result.quantity THEN RAISE EXCEPTION 'Insufficient stock at dispensing time'; END IF;
  UPDATE public.pharmacy_inventory SET stock_quantity=stock_quantity-result.quantity, updated_at=now() WHERE id=item.id;
  UPDATE public.pharmacy_pos_sales SET status='dispensed',dispensed_by=auth.uid(),dispensed_at=now() WHERE id=result.id RETURNING * INTO result;
  RETURN result;
END;
$$;
GRANT EXECUTE ON FUNCTION public.confirm_pharmacy_pos_sale(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.create_pharmacy_inventory_item(
  _drug_name TEXT, _brand_name TEXT, _generic_name TEXT, _strength TEXT, _form TEXT,
  _supplier TEXT, _batch_number TEXT, _expiry_date DATE, _stock_quantity INTEGER,
  _reorder_level INTEGER, _unit_price NUMERIC
)
RETURNS public.pharmacy_inventory LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE result public.pharmacy_inventory;
BEGIN
  IF NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'pharmacist')) THEN RAISE EXCEPTION 'Pharmacy role required'; END IF;
  IF length(trim(COALESCE(_drug_name,''))) < 2 THEN RAISE EXCEPTION 'Drug name is required'; END IF;
  IF COALESCE(_stock_quantity,0) < 0 OR COALESCE(_reorder_level,0) < 0 OR COALESCE(_unit_price,0) < 0 THEN RAISE EXCEPTION 'Inventory values cannot be negative'; END IF;
  INSERT INTO public.pharmacy_inventory(drug_name,brand_name,generic_name,strength,form,supplier,batch_number,expiry_date,stock_quantity,reorder_level,unit_price)
  VALUES(trim(_drug_name),NULLIF(trim(_brand_name),''),NULLIF(trim(_generic_name),''),NULLIF(trim(_strength),''),NULLIF(trim(_form),''),NULLIF(trim(_supplier),''),NULLIF(trim(_batch_number),''),_expiry_date,COALESCE(_stock_quantity,0),COALESCE(_reorder_level,0),COALESCE(_unit_price,0))
  RETURNING * INTO result;
  RETURN result;
END;
$$;
GRANT EXECUTE ON FUNCTION public.create_pharmacy_inventory_item(TEXT,TEXT,TEXT,TEXT,TEXT,TEXT,TEXT,DATE,INTEGER,INTEGER,NUMERIC) TO authenticated;