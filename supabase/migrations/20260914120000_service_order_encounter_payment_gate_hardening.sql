-- Harden the encounter -> service order -> payment -> department boundary.
-- Preserve the existing client-facing RPC signatures and legacy queue columns.

CREATE OR REPLACE FUNCTION public.validate_service_order_encounter()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_encounter public.encounters;
BEGIN
  IF NEW.encounter_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT * INTO v_encounter
  FROM public.encounters
  WHERE id = NEW.encounter_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Encounter not found';
  END IF;

  IF v_encounter.patient_id <> NEW.patient_id THEN
    RAISE EXCEPTION 'Service order patient does not match encounter patient';
  END IF;

  IF v_encounter.status IN ('completed','cancelled') THEN
    RAISE EXCEPTION 'Cannot create a service order for a completed or cancelled encounter';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS service_order_encounter_guard ON public.service_orders;
CREATE TRIGGER service_order_encounter_guard
BEFORE INSERT OR UPDATE OF encounter_id, patient_id ON public.service_orders
FOR EACH ROW
EXECUTE FUNCTION public.validate_service_order_encounter();

CREATE OR REPLACE FUNCTION public.create_imaging_order_with_payment_gate(
  _patient_id uuid,
  _encounter_id uuid DEFAULT NULL::uuid,
  _modality text DEFAULT 'X-Ray'::text,
  _study_name text DEFAULT 'General study'::text,
  _body_site text DEFAULT NULL::text,
  _priority text DEFAULT 'routine'::text,
  _clinical_indication text DEFAULT NULL::text,
  _amount numeric DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_imaging_id uuid;
  v_service_id uuid;
  v_status text;
  v_encounter_status text;
  v_encounter_patient uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (
    public.has_role(v_uid,'admin') OR
    public.has_role(v_uid,'practitioner') OR
    public.has_role(v_uid,'nurse') OR
    public.has_role(v_uid,'midwife') OR
    public.has_role(v_uid,'front_desk')
  ) THEN
    RAISE EXCEPTION 'Imaging order access required';
  END IF;
  IF _patient_id IS NULL OR NULLIF(trim(_study_name),'') IS NULL THEN
    RAISE EXCEPTION 'Patient and study name are required';
  END IF;
  IF COALESCE(_amount,0) < 0 THEN RAISE EXCEPTION 'Amount cannot be negative'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.patients WHERE id = _patient_id) THEN
    RAISE EXCEPTION 'Patient not found';
  END IF;

  IF _encounter_id IS NOT NULL THEN
    SELECT status, patient_id
      INTO v_encounter_status, v_encounter_patient
    FROM public.encounters
    WHERE id = _encounter_id;

    IF NOT FOUND THEN RAISE EXCEPTION 'Encounter not found'; END IF;
    IF v_encounter_patient <> _patient_id THEN
      RAISE EXCEPTION 'Imaging order patient does not match encounter patient';
    END IF;
    IF v_encounter_status IN ('completed','cancelled') THEN
      RAISE EXCEPTION 'Cannot create an imaging order for a completed or cancelled encounter';
    END IF;
  END IF;

  INSERT INTO public.imaging_orders(
    patient_id, encounter_id, modality, study_name, body_site, priority,
    clinical_indication, amount, status, requested_by
  )
  VALUES (
    _patient_id, _encounter_id, trim(_modality), trim(_study_name),
    NULLIF(trim(_body_site),''), COALESCE(NULLIF(trim(_priority),''),'routine'),
    NULLIF(trim(_clinical_indication),''), COALESCE(_amount,0),
    CASE WHEN COALESCE(_amount,0) > 0 THEN 'pending_payment_approval' ELSE 'released' END,
    v_uid
  )
  RETURNING id, status INTO v_imaging_id, v_status;

  IF COALESCE(_amount,0) > 0 THEN
    INSERT INTO public.service_orders(
      patient_id, encounter_id, department, service_name, amount, status,
      requested_by, related_entity_id, order_type, service_code,
      payment_required, created_by, notes
    )
    VALUES (
      _patient_id, _encounter_id, 'imaging', trim(_study_name), COALESCE(_amount,0),
      'pending_payment_approval', v_uid, v_imaging_id, 'imaging',
      upper(trim(_modality)), true, v_uid, NULLIF(trim(_clinical_indication),'')
    )
    RETURNING id INTO v_service_id;

    UPDATE public.imaging_orders
    SET service_order_id = v_service_id
    WHERE id = v_imaging_id;
  END IF;

  RETURN jsonb_build_object(
    'imaging_order_id', v_imaging_id,
    'service_order_id', v_service_id,
    'status', v_status
  );
END;
$function$;

-- The live database contains a legacy boolean-returning overload. Replace it
-- with the service-order row expected by the current frontend workflow.
DROP FUNCTION IF EXISTS public.release_service_order(uuid, text);

CREATE FUNCTION public.release_service_order(
  _service_order_id uuid,
  _reason text DEFAULT 'Payment received'
)
RETURNS public.service_orders
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.service_orders;
  v_paid numeric(12,2) := 0;
  v_override boolean := false;
  v_encounter_status text;
BEGIN
  IF auth.uid() IS NULL OR NOT (
    public.has_role(auth.uid(),'admin') OR
    public.has_role(auth.uid(),'accountant') OR
    public.has_role(auth.uid(),'front_desk')
  ) THEN
    RAISE EXCEPTION 'Accounts release permission required';
  END IF;

  SELECT * INTO v_order
  FROM public.service_orders
  WHERE id = _service_order_id
  FOR UPDATE;

  IF NOT FOUND THEN RAISE EXCEPTION 'Service order not found'; END IF;

  IF v_order.encounter_id IS NOT NULL THEN
    SELECT status INTO v_encounter_status
    FROM public.encounters
    WHERE id = v_order.encounter_id;

    IF NOT FOUND THEN RAISE EXCEPTION 'Linked encounter not found'; END IF;
    IF v_encounter_status IN ('completed','cancelled') THEN
      RAISE EXCEPTION 'Cannot release a service order linked to a completed or cancelled encounter';
    END IF;
  END IF;

  -- Release is idempotent: an already released/in-progress/completed order is
  -- returned unchanged rather than creating another queue entry.
  IF v_order.status <> 'pending_payment_approval' THEN
    RETURN v_order;
  END IF;

  SELECT COALESCE(SUM(p.amount),0)
    INTO v_paid
  FROM public.payments p
  WHERE p.invoice_id = v_order.invoice_id
    AND (
      p.paid_at IS NOT NULL
      OR lower(COALESCE(p.status,'')) IN ('paid','completed','confirmed','success','successful')
    );

  SELECT EXISTS (
    SELECT 1
    FROM public.billing_overrides b
    WHERE b.service_order_id = v_order.id
  ) INTO v_override;

  IF v_order.payment_required
     AND v_order.amount > 0
     AND (v_order.invoice_id IS NULL OR v_paid < v_order.amount)
     AND NOT v_override THEN
    RAISE EXCEPTION 'Payment approval is required before release';
  END IF;

  UPDATE public.service_orders
  SET status = 'released',
      approved_at = now(),
      approved_by = auth.uid(),
      updated_at = now()
  WHERE id = v_order.id
    AND status = 'pending_payment_approval'
  RETURNING * INTO v_order;

  IF NOT FOUND THEN
    SELECT * INTO v_order FROM public.service_orders WHERE id = _service_order_id;
    RETURN v_order;
  END IF;

  -- Keep both the current queue linkage and the legacy queue contract in sync.
  INSERT INTO public.department_queues(
    service_order_id,
    patient_id,
    department,
    related_encounter_id,
    related_invoice_id,
    payment_required,
    payment_satisfied,
    priority,
    reason,
    created_by,
    queued_at,
    status
  )
  VALUES (
    v_order.id,
    v_order.patient_id,
    v_order.department,
    v_order.encounter_id,
    v_order.invoice_id,
    v_order.payment_required,
    true,
    'normal',
    v_order.service_name,
    auth.uid(),
    now(),
    'queued'
  )
  ON CONFLICT (service_order_id) DO UPDATE
  SET payment_satisfied = true,
      status = CASE
        WHEN public.department_queues.status = 'cancelled' THEN 'queued'
        ELSE public.department_queues.status
      END,
      updated_at = now();

  IF v_order.order_type = 'imaging' AND v_order.related_entity_id IS NOT NULL THEN
    UPDATE public.imaging_orders
    SET status = 'released', updated_at = now()
    WHERE id = v_order.related_entity_id
      AND service_order_id = v_order.id
      AND status = 'pending_payment_approval';
  END IF;

  RETURN v_order;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.release_service_order(uuid,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.release_service_order(uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_imaging_order_with_payment_gate(uuid,uuid,text,text,text,text,text,numeric) TO authenticated;

COMMENT ON FUNCTION public.validate_service_order_encounter() IS
  'Rejects service orders whose encounter is missing, belongs to another patient, or is terminal.';
COMMENT ON FUNCTION public.release_service_order(uuid,text) IS
  'Accounts payment gate for service orders; idempotent release with encounter and department-queue integrity.';
