-- Enforce patient/encounter/invoice linkage at the service-order security boundary.
-- The caller may provide identifiers, but cannot bind a new order to unrelated
-- clinical or financial records.

CREATE OR REPLACE FUNCTION public.create_service_order(
  _patient_id uuid,
  _encounter_id uuid DEFAULT NULL::uuid,
  _department text DEFAULT 'other'::text,
  _service_name text DEFAULT NULL::text,
  _amount numeric DEFAULT 0,
  _related_entity_id uuid DEFAULT NULL::uuid,
  _notes text DEFAULT NULL::text,
  _requested_by uuid DEFAULT NULL::uuid,
  _invoice_id uuid DEFAULT NULL::uuid,
  _invoice_item_id uuid DEFAULT NULL::uuid,
  _order_type text DEFAULT 'service'::text,
  _service_code text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.service_orders;
  v_patient_id uuid;
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

  IF _encounter_id IS NOT NULL THEN
    SELECT patient_id INTO v_patient_id
    FROM public.encounters
    WHERE id=_encounter_id;

    IF NOT FOUND OR v_patient_id IS DISTINCT FROM _patient_id THEN
      RAISE EXCEPTION 'Encounter does not belong to patient';
    END IF;
  END IF;

  IF _invoice_id IS NOT NULL THEN
    SELECT patient_id INTO v_patient_id
    FROM public.invoices
    WHERE id=_invoice_id;

    IF NOT FOUND OR v_patient_id IS DISTINCT FROM _patient_id THEN
      RAISE EXCEPTION 'Invoice does not belong to patient';
    END IF;

    IF _encounter_id IS NOT NULL AND EXISTS (
      SELECT 1 FROM public.invoices
      WHERE id=_invoice_id AND encounter_id IS NOT NULL
        AND encounter_id IS DISTINCT FROM _encounter_id
    ) THEN
      RAISE EXCEPTION 'Invoice does not belong to encounter';
    END IF;
  END IF;

  IF _invoice_item_id IS NOT NULL THEN
    IF _invoice_id IS NULL THEN
      RAISE EXCEPTION 'Invoice is required when invoice item is supplied';
    END IF;

    IF NOT EXISTS (
      SELECT 1
      FROM public.invoice_items ii
      WHERE ii.id=_invoice_item_id
        AND ii.invoice_id=_invoice_id
        AND ii.patient_id=_patient_id
    ) THEN
      RAISE EXCEPTION 'Invoice item does not belong to patient invoice';
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

  RETURN to_jsonb(v_order);
END;
$$;

REVOKE ALL ON FUNCTION public.create_service_order(
  uuid,uuid,text,text,numeric,uuid,text,uuid,uuid,uuid,text,text
) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.create_service_order(
  uuid,uuid,text,text,numeric,uuid,text,uuid,uuid,uuid,text,text
) TO authenticated;
