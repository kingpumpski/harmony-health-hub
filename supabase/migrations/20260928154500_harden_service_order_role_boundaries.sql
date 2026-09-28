-- Replace the broad is_clinical_staff helper in client-facing mutations.
-- The helper includes non-care roles for legacy compatibility and must not be
-- used as the authorization boundary for these writes.

CREATE OR REPLACE FUNCTION public.cancel_service_order(
  _service_order_id uuid,
  _reason text DEFAULT 'Cancelled'
)
RETURNS public.service_orders
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE v_order public.service_orders;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (
    public.has_role(auth.uid(),'admin')
    OR public.has_role(auth.uid(),'accountant')
    OR public.has_role(auth.uid(),'front_desk')
    OR public.has_role(auth.uid(),'practitioner')
    OR public.has_role(auth.uid(),'nurse')
    OR public.has_role(auth.uid(),'midwife')
    OR public.has_role(auth.uid(),'specialist_nurse')
    OR public.has_role(auth.uid(),'lab_technician')
    OR public.has_role(auth.uid(),'radiologist')
    OR public.has_role(auth.uid(),'radiology_technician')
    OR public.has_role(auth.uid(),'pharmacist')
  ) THEN RAISE EXCEPTION 'Authorised staff required'; END IF;

  UPDATE public.service_orders
  SET status='cancelled',
      notes=trim(COALESCE(_reason,notes,'Cancelled')),
      cancelled_at=now(),
      release_reason=COALESCE(release_reason,trim(COALESCE(_reason,'Cancelled'))),
      updated_at=now()
  WHERE id=_service_order_id
    AND status IN ('pending_payment_approval','released','in_progress')
  RETURNING * INTO v_order;

  IF NOT FOUND THEN RAISE EXCEPTION 'Order cannot be cancelled in its current state'; END IF;

  UPDATE public.department_queues
  SET status='cancelled',updated_at=now()
  WHERE service_order_id=v_order.id;

  RETURN v_order;
END;
$function$;

CREATE OR REPLACE FUNCTION public.create_anesthetic_assessment(
  _patient_id uuid,
  _asa_class text DEFAULT 'I',
  _airway_assessment text DEFAULT NULL,
  _cardiovascular text DEFAULT NULL,
  _respiratory text DEFAULT NULL,
  _allergies text DEFAULT NULL,
  _medications text DEFAULT NULL,
  _fasting_status text DEFAULT NULL,
  _conclusions text DEFAULT NULL,
  _cleared_for_procedure boolean DEFAULT false
)
RETURNS public.anesthetic_assessments
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE uid uuid:=auth.uid(); result public.anesthetic_assessments;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (
    public.has_role(uid,'admin')
    OR public.has_role(uid,'practitioner')
    OR public.has_role(uid,'nurse')
    OR public.has_role(uid,'midwife')
    OR public.has_role(uid,'specialist_nurse')
  ) THEN RAISE EXCEPTION 'Not authorized to create anesthetic assessments'; END IF;

  IF NOT EXISTS (SELECT 1 FROM public.patients WHERE id=_patient_id) THEN
    RAISE EXCEPTION 'Patient not found';
  END IF;
  IF NULLIF(pg_catalog.btrim(_asa_class),'') IS NULL THEN RAISE EXCEPTION 'ASA class is required'; END IF;
  IF pg_catalog.btrim(_asa_class) NOT IN ('I','II','III','IV','V','VI') THEN RAISE EXCEPTION 'Invalid ASA class'; END IF;

  INSERT INTO public.anesthetic_assessments(
    patient_id,asa_class,airway_assessment,cardiovascular,respiratory,
    allergies,medications,fasting_status,conclusions,cleared_for_procedure,
    cleared_by,assessed_by,status
  ) VALUES (
    _patient_id,pg_catalog.btrim(_asa_class),
    NULLIF(pg_catalog.btrim(_airway_assessment),''),
    NULLIF(pg_catalog.btrim(_cardiovascular),''),
    NULLIF(pg_catalog.btrim(_respiratory),''),
    NULLIF(pg_catalog.btrim(_allergies),''),
    NULLIF(pg_catalog.btrim(_medications),''),
    NULLIF(pg_catalog.btrim(_fasting_status),''),
    NULLIF(pg_catalog.btrim(_conclusions),''),
    COALESCE(_cleared_for_procedure,FALSE),
    CASE WHEN COALESCE(_cleared_for_procedure,FALSE) THEN uid ELSE NULL END,
    uid,'completed'
  ) RETURNING * INTO result;
  RETURN result;
END;
$function$;

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
AS $function$
DECLARE v_order public.service_orders;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (
    public.has_role(auth.uid(),'admin')
    OR public.has_role(auth.uid(),'front_desk')
    OR public.has_role(auth.uid(),'practitioner')
    OR public.has_role(auth.uid(),'nurse')
    OR public.has_role(auth.uid(),'midwife')
    OR public.has_role(auth.uid(),'specialist_nurse')
    OR public.has_role(auth.uid(),'lab_technician')
    OR public.has_role(auth.uid(),'radiologist')
    OR public.has_role(auth.uid(),'radiology_technician')
    OR public.has_role(auth.uid(),'pharmacist')
  ) THEN RAISE EXCEPTION 'Service order creation denied'; END IF;

  IF _patient_id IS NULL OR NULLIF(pg_catalog.btrim(_service_name),'') IS NULL THEN
    RAISE EXCEPTION 'Patient and service name are required';
  END IF;

  IF _encounter_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.encounters e WHERE e.id=_encounter_id AND e.patient_id=_patient_id
  ) THEN RAISE EXCEPTION 'Encounter does not belong to this patient'; END IF;

  INSERT INTO public.service_orders(
    patient_id,encounter_id,department,service_name,amount,
    related_entity_id,notes,requested_by,invoice_id,invoice_item_id,
    order_type,service_code,status,created_by
  ) VALUES (
    _patient_id,_encounter_id,_department,_service_name,COALESCE(_amount,0),
    _related_entity_id,_notes,auth.uid(),_invoice_id,_invoice_item_id,
    COALESCE(_order_type,'service'),_service_code,'pending_payment_approval',auth.uid()
  ) RETURNING * INTO v_order;

  RETURN to_jsonb(v_order);
END;
$function$;

REVOKE ALL ON FUNCTION public.cancel_service_order(uuid,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.cancel_service_order(uuid,text) TO authenticated;
REVOKE ALL ON FUNCTION public.create_anesthetic_assessment(uuid,text,text,text,text,text,text,text,text,boolean) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.create_anesthetic_assessment(uuid,text,text,text,text,text,text,text,text,boolean) TO authenticated;
REVOKE ALL ON FUNCTION public.create_service_order(uuid,uuid,text,text,numeric,uuid,text,uuid,uuid,uuid,text,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.create_service_order(uuid,uuid,text,text,numeric,uuid,text,uuid,uuid,uuid,text,text) TO authenticated;
