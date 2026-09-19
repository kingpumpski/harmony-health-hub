-- Reconcile service-order client workflow with RLS-protected writes.
CREATE OR REPLACE FUNCTION public.create_service_order(
  _patient_id UUID, _encounter_id UUID DEFAULT NULL, _department TEXT DEFAULT 'other',
  _service_name TEXT DEFAULT NULL, _amount NUMERIC DEFAULT 0, _related_entity_id UUID DEFAULT NULL,
  _notes TEXT DEFAULT NULL, _requested_by UUID DEFAULT NULL, _invoice_id UUID DEFAULT NULL,
  _invoice_item_id UUID DEFAULT NULL, _order_type TEXT DEFAULT 'service', _service_code TEXT DEFAULT NULL
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_order public.service_orders;
BEGIN
  IF NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'front_desk') OR public.is_clinical_staff(auth.uid())) THEN
    RAISE EXCEPTION 'Service order creation denied';
  END IF;
  IF _patient_id IS NULL OR NULLIF(TRIM(_service_name),'') IS NULL THEN
    RAISE EXCEPTION 'Patient and service name are required';
  END IF;
  INSERT INTO public.service_orders
    (patient_id,encounter_id,department,service_name,amount,related_entity_id,notes,requested_by,
     invoice_id,invoice_item_id,order_type,service_code,status,created_by)
  VALUES
    (_patient_id,_encounter_id,_department,_service_name,COALESCE(_amount,0),_related_entity_id,_notes,
     COALESCE(_requested_by,auth.uid()),_invoice_id,_invoice_item_id,COALESCE(_order_type,'service'),
     _service_code,'pending_payment_approval',auth.uid())
  RETURNING * INTO v_order;
  RETURN to_jsonb(v_order);
END; $$;

REVOKE ALL ON FUNCTION public.create_service_order(UUID,UUID,TEXT,TEXT,NUMERIC,UUID,TEXT,UUID,UUID,UUID,TEXT,TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_service_order(UUID,UUID,TEXT,TEXT,NUMERIC,UUID,TEXT,UUID,UUID,UUID,TEXT,TEXT) TO authenticated;

DROP POLICY IF EXISTS "service_orders_authenticated_read" ON public.service_orders;
CREATE POLICY "service_orders_staff_read" ON public.service_orders
FOR SELECT TO authenticated
USING (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'accountant')
  OR public.has_role(auth.uid(),'front_desk') OR public.is_clinical_staff(auth.uid()));

NOTIFY pgrst, 'reload schema';
