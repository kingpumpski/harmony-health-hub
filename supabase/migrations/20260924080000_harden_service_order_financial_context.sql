CREATE OR REPLACE FUNCTION public.create_service_order(
  _patient_id uuid,
  _encounter_id uuid DEFAULT NULL,
  _department text DEFAULT 'other',
  _service_name text DEFAULT NULL,
  _amount numeric DEFAULT 0,
  _related_entity_id uuid DEFAULT NULL,
  _notes text DEFAULT NULL,
  _requested_by uuid DEFAULT NULL,
  _invoice_id uuid DEFAULT NULL,
  _invoice_item_id uuid DEFAULT NULL,
  _order_type text DEFAULT 'service',
  _service_code text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.service_orders;
  v_invoice_patient uuid;
  v_invoice_encounter uuid;
  v_item_invoice uuid;
  v_item_patient uuid;
  v_item_service_order uuid;
  v_encounter_patient uuid;
BEGIN
  IF NOT (
    public.has_role(auth.uid(),'admin')
    OR public.has_role(auth.uid(),'front_desk')
    OR public.is_clinical_staff(auth.uid())
  ) THEN
    RAISE EXCEPTION 'Service order creation denied';
  END IF;

  IF _patient_id IS NULL OR NULLIF(TRIM(_service_name),'') IS NULL THEN
    RAISE EXCEPTION 'Patient and service name are required';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.patients WHERE id=_patient_id) THEN
    RAISE EXCEPTION 'Patient not found';
  END IF;

  IF COALESCE(_amount,0) < 0 THEN
    RAISE EXCEPTION 'Amount cannot be negative';
  END IF;

  IF _encounter_id IS NOT NULL THEN
    SELECT patient_id INTO v_encounter_patient
    FROM public.encounters WHERE id=_encounter_id;
    IF NOT FOUND OR v_encounter_patient IS DISTINCT FROM _patient_id THEN
      RAISE EXCEPTION 'Encounter does not belong to patient';
    END IF;
  END IF;

  IF _invoice_id IS NOT NULL THEN
    SELECT patient_id,encounter_id INTO v_invoice_patient,v_invoice_encounter
    FROM public.invoices WHERE id=_invoice_id;
    IF NOT FOUND OR v_invoice_patient IS DISTINCT FROM _patient_id THEN
      RAISE EXCEPTION 'Invoice does not belong to patient';
    END IF;
    IF _encounter_id IS NOT NULL
       AND v_invoice_encounter IS NOT NULL
       AND v_invoice_encounter IS DISTINCT FROM _encounter_id THEN
      RAISE EXCEPTION 'Invoice does not match encounter';
    END IF;
  END IF;

  IF _invoice_item_id IS NOT NULL THEN
    SELECT invoice_id,patient_id,service_order_id
      INTO v_item_invoice,v_item_patient,v_item_service_order
    FROM public.invoice_items
    WHERE id=_invoice_item_id
    FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Invoice item not found';
    END IF;
    IF v_item_patient IS DISTINCT FROM _patient_id THEN
      RAISE EXCEPTION 'Invoice item does not belong to patient';
    END IF;
    IF _invoice_id IS NULL OR v_item_invoice IS DISTINCT FROM _invoice_id THEN
      RAISE EXCEPTION 'Invoice item does not belong to invoice';
    END IF;
    IF v_item_service_order IS NOT NULL THEN
      RAISE EXCEPTION 'Invoice item is already linked to a service order';
    END IF;
  END IF;

  INSERT INTO public.service_orders (
    patient_id,encounter_id,department,service_name,amount,
    related_entity_id,notes,requested_by,invoice_id,invoice_item_id,
    order_type,service_code,status,created_by
  )
  VALUES (
    _patient_id,_encounter_id,_department,_service_name,COALESCE(_amount,0),
    _related_entity_id,_notes,auth.uid(),_invoice_id,_invoice_item_id,
    COALESCE(_order_type,'service'),_service_code,'pending_payment_approval',auth.uid()
  )
  RETURNING * INTO v_order;

  IF _invoice_item_id IS NOT NULL THEN
    UPDATE public.invoice_items
    SET service_order_id=v_order.id
    WHERE id=_invoice_item_id
      AND service_order_id IS NULL;
  END IF;

  RETURN to_jsonb(v_order);
END;
$$;

REVOKE ALL ON FUNCTION public.create_service_order(uuid,uuid,text,text,numeric,uuid,text,uuid,uuid,uuid,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_service_order(uuid,uuid,text,text,numeric,uuid,text,uuid,uuid,uuid,text,text) TO authenticated;
