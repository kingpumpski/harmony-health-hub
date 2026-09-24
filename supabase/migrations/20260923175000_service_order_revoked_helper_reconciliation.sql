-- Reconcile remaining SECURITY DEFINER service-order and coverage RPCs
-- that depended on the revoked arbitrary-user clinical helper.

CREATE OR REPLACE FUNCTION public.activate_patient_visit_coverage(
  _patient_id UUID,
  _source TEXT,
  _appointment_id UUID DEFAULT NULL,
  _authorization_date DATE DEFAULT CURRENT_DATE
)
RETURNS public.patient_visit_authorizations
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public
AS $$
DECLARE
  coverage RECORD;
  result public.patient_visit_authorizations;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF _source NOT IN ('appointment','accounts') THEN RAISE EXCEPTION 'Invalid activation source'; END IF;
  IF NOT (
    public.current_user_has_role('admin')
    OR public.current_user_has_role('accountant')
    OR public.current_user_has_role('front_desk')
    OR public.current_user_is_clinical_staff()
  ) THEN
    RAISE EXCEPTION 'Only authorised staff can activate visit coverage';
  END IF;

  SELECT * INTO coverage FROM public.patient_coverage_details(_patient_id);
  IF coverage.coverage_type IS NULL THEN
    RAISE EXCEPTION 'Patient has no active insurance or partnered-company coverage';
  END IF;
  IF _appointment_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.appointments
    WHERE id=_appointment_id AND patient_id=_patient_id
  ) THEN
    RAISE EXCEPTION 'Appointment does not belong to this patient';
  END IF;

  INSERT INTO public.patient_visit_authorizations(
    patient_id,authorization_date,coverage_type,payer_name,
    activated_by,activation_source,appointment_id,active
  )
  VALUES(
    _patient_id,_authorization_date,coverage.coverage_type,coverage.payer_name,
    auth.uid(),_source,_appointment_id,true
  )
  ON CONFLICT(patient_id,authorization_date) DO UPDATE SET
    coverage_type=EXCLUDED.coverage_type,
    payer_name=EXCLUDED.payer_name,
    activated_by=EXCLUDED.activated_by,
    activation_source=EXCLUDED.activation_source,
    appointment_id=COALESCE(EXCLUDED.appointment_id,patient_visit_authorizations.appointment_id),
    active=true
  RETURNING * INTO result;

  RETURN result;
END;
$$;

REVOKE ALL ON FUNCTION public.activate_patient_visit_coverage(UUID,TEXT,UUID,DATE) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.activate_patient_visit_coverage(UUID,TEXT,UUID,DATE) TO authenticated;


CREATE OR REPLACE FUNCTION public.create_service_order(
  _patient_id UUID,
  _encounter_id UUID DEFAULT NULL,
  _department TEXT DEFAULT 'other',
  _service_name TEXT DEFAULT NULL,
  _amount NUMERIC DEFAULT 0,
  _related_entity_id UUID DEFAULT NULL,
  _notes TEXT DEFAULT NULL,
  _requested_by UUID DEFAULT NULL,
  _invoice_id UUID DEFAULT NULL,
  _invoice_item_id UUID DEFAULT NULL,
  _order_type TEXT DEFAULT 'service',
  _service_code TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public
AS $$
DECLARE v_order public.service_orders;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (
    public.current_user_has_role('admin')
    OR public.current_user_has_role('front_desk')
    OR public.current_user_is_clinical_staff()
  ) THEN
    RAISE EXCEPTION 'Service order creation denied';
  END IF;
  IF _patient_id IS NULL OR NULLIF(TRIM(_service_name),'') IS NULL THEN
    RAISE EXCEPTION 'Patient and service name are required';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.patients
    WHERE id=_patient_id AND COALESCE(status,'active') <> 'inactive'
  ) THEN
    RAISE EXCEPTION 'Active patient not found';
  END IF;
  IF _encounter_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.encounters
    WHERE id=_encounter_id AND patient_id=_patient_id
  ) THEN
    RAISE EXCEPTION 'Encounter does not belong to this patient';
  END IF;

  INSERT INTO public.service_orders(
    patient_id,encounter_id,department,service_name,amount,
    related_entity_id,notes,requested_by,invoice_id,invoice_item_id,
    order_type,service_code,status,created_by
  )
  VALUES(
    _patient_id,_encounter_id,_department,_service_name,COALESCE(_amount,0),
    _related_entity_id,_notes,auth.uid(),_invoice_id,_invoice_item_id,
    COALESCE(_order_type,'service'),_service_code,'pending_payment_approval',auth.uid()
  )
  RETURNING * INTO v_order;
  RETURN to_jsonb(v_order);
END;
$$;

REVOKE ALL ON FUNCTION public.create_service_order(UUID,UUID,TEXT,TEXT,NUMERIC,UUID,TEXT,UUID,UUID,UUID,TEXT,TEXT) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.create_service_order(UUID,UUID,TEXT,TEXT,NUMERIC,UUID,TEXT,UUID,UUID,UUID,TEXT,TEXT) TO authenticated;


CREATE OR REPLACE FUNCTION public.cancel_service_order(
  _service_order_id UUID,
  _reason TEXT DEFAULT 'Cancelled'
)
RETURNS public.service_orders
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public
AS $$
DECLARE v_order public.service_orders;
BEGIN
  IF auth.uid() IS NULL OR NOT (
    public.current_user_has_role('admin')
    OR public.current_user_has_role('accountant')
    OR public.current_user_is_clinical_staff()
  ) THEN
    RAISE EXCEPTION 'Authorised staff required';
  END IF;

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
  UPDATE public.department_queues SET status='cancelled',updated_at=now()
  WHERE service_order_id=v_order.id;
  RETURN v_order;
END;
$$;

REVOKE ALL ON FUNCTION public.cancel_service_order(UUID,TEXT) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.cancel_service_order(UUID,TEXT) TO authenticated;


CREATE OR REPLACE FUNCTION public.mark_service_order_in_progress(_service_order_id UUID)
RETURNS public.service_orders
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public
AS $$
DECLARE v_order public.service_orders;
BEGIN
  IF auth.uid() IS NULL OR NOT public.current_user_is_clinical_staff() THEN
    RAISE EXCEPTION 'Clinical staff required';
  END IF;

  UPDATE public.service_orders so
  SET status='in_progress',
      started_at=COALESCE(started_at,now()),
      updated_at=now()
  WHERE so.id=_service_order_id
    AND so.status='released'
    AND EXISTS(
      SELECT 1 FROM public.profiles p
      WHERE p.id=auth.uid()
        AND lower(COALESCE(p.department,''))=lower(so.department)
    )
  RETURNING * INTO v_order;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order must be released and assigned to your department';
  END IF;

  UPDATE public.department_queues
  SET status='claimed',
      claimed_by=auth.uid(),
      assigned_to=auth.uid(),
      claimed_at=COALESCE(claimed_at,now()),
      updated_at=now()
  WHERE service_order_id=_service_order_id;

  RETURN v_order;
END;
$$;

REVOKE ALL ON FUNCTION public.mark_service_order_in_progress(UUID) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.mark_service_order_in_progress(UUID) TO authenticated;


CREATE OR REPLACE FUNCTION public.complete_service_order(_service_order_id UUID)
RETURNS public.service_orders
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public
AS $$
DECLARE v_order public.service_orders;
BEGIN
  IF auth.uid() IS NULL OR NOT public.current_user_is_clinical_staff() THEN
    RAISE EXCEPTION 'Clinical staff required';
  END IF;

  UPDATE public.service_orders so
  SET status='completed',
      completed_at=now(),
      updated_at=now()
  WHERE so.id=_service_order_id
    AND so.status='in_progress'
    AND EXISTS(
      SELECT 1 FROM public.profiles p
      WHERE p.id=auth.uid()
        AND lower(COALESCE(p.department,''))=lower(so.department)
    )
  RETURNING * INTO v_order;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order must be in progress and assigned to your department';
  END IF;

  UPDATE public.department_queues
  SET status='completed',completed_at=now(),updated_at=now()
  WHERE service_order_id=_service_order_id;

  RETURN v_order;
END;
$$;

REVOKE ALL ON FUNCTION public.complete_service_order(UUID) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.complete_service_order(UUID) TO authenticated;


CREATE OR REPLACE FUNCTION public.get_department_queue(
  _department TEXT,
  _limit INTEGER DEFAULT 100
)
RETURNS TABLE(
  id UUID,
  department TEXT,
  status TEXT,
  queued_at TIMESTAMPTZ,
  service_order_id UUID,
  service_name TEXT,
  amount NUMERIC,
  service_order_status TEXT,
  patient_id UUID,
  patient_first_name TEXT,
  patient_last_name TEXT,
  patient_code TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public
AS $$
DECLARE v_department TEXT:=NULLIF(btrim(_department),'');
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF v_department IS NULL THEN RETURN; END IF;
  IF _limit IS NULL OR _limit < 1 OR _limit > 500 THEN
    RAISE EXCEPTION 'Invalid queue limit';
  END IF;
  IF NOT (
    public.current_user_has_role('admin')
    OR public.current_user_has_role('accountant')
    OR public.current_user_is_clinical_staff()
  ) THEN
    RAISE EXCEPTION 'Department queue access denied';
  END IF;
  IF NOT EXISTS(
    SELECT 1 FROM public.profiles p
    WHERE p.id=auth.uid()
      AND lower(COALESCE(p.department,''))=lower(v_department)
  ) AND NOT public.current_user_has_role('admin') THEN
    RAISE EXCEPTION 'Department queue access denied for this department';
  END IF;

  RETURN QUERY
  SELECT q.id,q.department,q.status,q.queued_at,q.service_order_id,
         so.service_name,so.amount,so.status,so.patient_id,
         p.first_name,p.last_name,p.patient_code
  FROM public.department_queues q
  JOIN public.service_orders so ON so.id=q.service_order_id
  JOIN public.patients p ON p.id=so.patient_id
  WHERE lower(q.department)=lower(v_department)
    AND q.status IN ('queued','claimed')
  ORDER BY q.queued_at ASC
  LIMIT _limit;
END;
$$;

REVOKE ALL ON FUNCTION public.get_department_queue(TEXT,INTEGER) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_department_queue(TEXT,INTEGER) TO authenticated;
