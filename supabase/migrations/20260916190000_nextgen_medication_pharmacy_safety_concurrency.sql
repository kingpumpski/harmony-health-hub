-- Next-generation medication/pharmacy safety boundary.
-- Reuses the existing MAR and pharmacy lifecycle RPCs; no parallel service is introduced.
-- Direct client mutation remains revoked. All high-risk state changes stay server-authoritative.

CREATE OR REPLACE FUNCTION public.guard_medication_administration_integrity()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path=public
AS $$
BEGIN
  IF NEW.status = 'administered' THEN
    IF NEW.administered_by IS NULL OR NEW.administered_at IS NULL THEN
      RAISE EXCEPTION 'Administered medication requires actor and administration timestamp';
    END IF;
  END IF;

  IF NEW.status IN ('held','refused','omitted')
     AND NULLIF(trim(COALESCE(NEW.reason,'')),'') IS NULL THEN
    RAISE EXCEPTION 'Held, refused, or omitted medication requires a documented reason';
  END IF;

  IF NEW.status = 'scheduled' AND NEW.administered_by IS NOT NULL THEN
    RAISE EXCEPTION 'Scheduled medication cannot retain an administering actor';
  END IF;

  IF NEW.status = 'cancelled' AND NEW.administered_at IS NOT NULL THEN
    RAISE EXCEPTION 'Cancelled medication cannot have an administration timestamp';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS t_mar_integrity_guard ON public.medication_administrations;
CREATE TRIGGER t_mar_integrity_guard
BEFORE INSERT OR UPDATE ON public.medication_administrations
FOR EACH ROW EXECUTE FUNCTION public.guard_medication_administration_integrity();

CREATE OR REPLACE FUNCTION public.transition_medication_administration(
  _record_id UUID,
  _status TEXT,
  _reason TEXT DEFAULT NULL,
  _notes TEXT DEFAULT NULL,
  _witnessed_by UUID DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public
AS $$
DECLARE
  v public.medication_administrations;
  reason_text TEXT := NULLIF(trim(COALESCE(_reason,'')), '');
  window_minutes INTEGER;
BEGIN
  IF auth.uid() IS NULL OR NOT (
    public.has_role(auth.uid(),'admin') OR
    public.has_role(auth.uid(),'practitioner') OR
    public.has_role(auth.uid(),'nurse') OR
    public.has_role(auth.uid(),'midwife') OR
    public.has_role(auth.uid(),'specialist_nurse') OR
    public.has_role(auth.uid(),'pharmacist')
  ) THEN
    RAISE EXCEPTION 'Not authorized to administer medication';
  END IF;

  IF _status NOT IN ('administered','held','refused','omitted','cancelled') THEN
    RAISE EXCEPTION 'Invalid medication status';
  END IF;

  SELECT * INTO v
  FROM public.medication_administrations
  WHERE id=_record_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Medication administration record not found';
  END IF;

  IF v.status IN ('cancelled','administered','refused','omitted') THEN
    RAISE EXCEPTION 'Medication record is already closed';
  END IF;

  IF _status IN ('held','refused','omitted') AND reason_text IS NULL THEN
    RAISE EXCEPTION 'A clinical reason is required for held, refused, or omitted medication';
  END IF;

  IF _status='administered' AND _witnessed_by IS NOT NULL AND _witnessed_by=auth.uid() THEN
    RAISE EXCEPTION 'Witness must be a different authenticated user';
  END IF;

  IF _witnessed_by IS NOT NULL AND NOT (
    public.has_role(_witnessed_by,'admin') OR
    public.has_role(_witnessed_by,'practitioner') OR
    public.has_role(_witnessed_by,'nurse') OR
    public.has_role(_witnessed_by,'midwife') OR
    public.has_role(_witnessed_by,'specialist_nurse') OR
    public.has_role(_witnessed_by,'pharmacist')
  ) THEN
    RAISE EXCEPTION 'Witness must be an authorized clinical user';
  END IF;

  IF _status='administered' AND v.scheduled_at IS NOT NULL THEN
    window_minutes := GREATEST(COALESCE(v.due_window_minutes,30),5);
    IF now() < v.scheduled_at - make_interval(mins => window_minutes) THEN
      RAISE EXCEPTION 'Medication is outside its permitted administration window';
    END IF;
  END IF;

  UPDATE public.medication_administrations
  SET status=_status,
      reason=CASE WHEN reason_text IS NOT NULL THEN reason_text ELSE reason END,
      notes=CASE WHEN _notes IS NOT NULL THEN NULLIF(trim(_notes),'') ELSE notes END,
      administered_at=CASE WHEN _status='administered' THEN now() ELSE administered_at END,
      administered_by=CASE WHEN _status IN ('administered','held','refused','omitted') THEN auth.uid() ELSE administered_by END,
      witnessed_by=CASE WHEN _status='administered' THEN COALESCE(_witnessed_by,witnessed_by) ELSE witnessed_by END,
      updated_at=now()
  WHERE id=_record_id;

  PERFORM public.record_system_audit(
    'medication_administration_'||_status,
    'clinical',
    'medication_administrations',
    _record_id,
    CASE WHEN _status='administered' THEN 'info' ELSE 'warning' END,
    jsonb_build_object(
      'record_id',_record_id,
      'patient_id',v.patient_id,
      'status',_status,
      'administered_by',auth.uid(),
      'witnessed_by',_witnessed_by,
      'reason',reason_text,
      'timestamp',now()
    )
  );

  RETURN _record_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.reopen_medication_administration(
  _record_id UUID,
  _reason TEXT
)
RETURNS public.medication_administrations
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public
AS $$
DECLARE
  v public.medication_administrations;
  reason_text TEXT := NULLIF(trim(COALESCE(_reason,'')), '');
BEGIN
  IF auth.uid() IS NULL OR NOT (
    public.has_role(auth.uid(),'admin') OR
    public.has_role(auth.uid(),'practitioner') OR
    public.has_role(auth.uid(),'nurse') OR
    public.has_role(auth.uid(),'midwife') OR
    public.has_role(auth.uid(),'specialist_nurse')
  ) THEN
    RAISE EXCEPTION 'Authorized clinical role required';
  END IF;

  IF reason_text IS NULL THEN
    RAISE EXCEPTION 'A professional reason is required to reopen a medication record';
  END IF;

  SELECT * INTO v FROM public.medication_administrations WHERE id=_record_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Medication administration record not found'; END IF;
  IF v.status NOT IN ('administered','held','refused','omitted') THEN
    RAISE EXCEPTION 'Only a closed documented medication record can be reopened';
  END IF;

  UPDATE public.medication_administrations
  SET status='scheduled',
      administered_at=NULL,
      administered_by=NULL,
      witnessed_by=NULL,
      reason=NULL,
      locked_at=NULL,
      lock_reason=NULL,
      reopened_at=now(),
      reopen_reason=reason_text,
      updated_at=now()
  WHERE id=_record_id
  RETURNING * INTO v;

  PERFORM public.record_system_audit(
    'medication_administration_reopened',
    'clinical',
    'medication_administrations',
    _record_id,
    'warning',
    jsonb_build_object('patient_id',v.patient_id,'reopened_by',auth.uid(),'reason',reason_text,'reopened_at',now())
  );

  RETURN v;
END;
$$;

CREATE OR REPLACE FUNCTION public.guard_pharmacy_inventory_nonnegative()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path=public
AS $$
BEGIN
  IF COALESCE(NEW.stock_quantity,0) < 0 THEN
    RAISE EXCEPTION 'Pharmacy stock cannot be negative';
  END IF;
  IF COALESCE(NEW.unit_price,0) < 0 THEN
    RAISE EXCEPTION 'Pharmacy unit price cannot be negative';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS t_pharmacy_inventory_nonnegative ON public.pharmacy_inventory;
CREATE TRIGGER t_pharmacy_inventory_nonnegative
BEFORE INSERT OR UPDATE ON public.pharmacy_inventory
FOR EACH ROW EXECUTE FUNCTION public.guard_pharmacy_inventory_nonnegative();

CREATE OR REPLACE FUNCTION public.confirm_pharmacy_dispense(_plan_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public
AS $$
DECLARE
  p public.pharmacy_dispensing_plans;
  i public.pharmacy_inventory;
  order_status text;
  encounter_status text;
BEGIN
  IF auth.uid() IS NULL OR NOT(public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'pharmacist')) THEN
    RAISE EXCEPTION 'Pharmacy role required';
  END IF;

  SELECT * INTO p FROM public.pharmacy_dispensing_plans WHERE id=_plan_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Dispensing plan not found'; END IF;
  IF p.status='dispensed' THEN
    RETURN jsonb_build_object('plan_id',p.id,'status','dispensed','dispensed_by',p.dispensed_by,'idempotent',true);
  END IF;
  IF p.status<>'unpaid' THEN RAISE EXCEPTION 'Dispensing plan is already processed'; END IF;

  SELECT status INTO order_status FROM public.service_orders WHERE id=p.service_order_id FOR UPDATE;
  IF order_status NOT IN('released','in_progress') THEN
    RAISE EXCEPTION 'Payment has not been received or the pharmacy order has not been released';
  END IF;

  SELECT e.status INTO encounter_status
  FROM public.encounters e
  JOIN public.prescriptions r ON r.encounter_id=e.id
  WHERE r.id=p.prescription_id;
  IF encounter_status IN('completed','cancelled') THEN
    RAISE EXCEPTION 'Cannot dispense against a closed encounter';
  END IF;

  SELECT * INTO i FROM public.pharmacy_inventory WHERE id=p.inventory_id FOR UPDATE;
  IF NOT FOUND OR NOT i.active THEN RAISE EXCEPTION 'Inventory item is unavailable'; END IF;
  IF i.stock_quantity<p.prepared_quantity THEN RAISE EXCEPTION 'Insufficient stock at dispensing time'; END IF;

  UPDATE public.pharmacy_inventory
  SET stock_quantity=stock_quantity-p.prepared_quantity,updated_at=now()
  WHERE id=i.id AND stock_quantity>=p.prepared_quantity;
  IF NOT FOUND THEN RAISE EXCEPTION 'Stock changed concurrently; retry dispensing'; END IF;

  UPDATE public.pharmacy_dispensing_plans
  SET status='dispensed',dispensed_by=auth.uid(),dispensed_at=now(),updated_at=now()
  WHERE id=p.id AND status='unpaid';
  IF NOT FOUND THEN RAISE EXCEPTION 'Dispensing plan changed concurrently; retry'; END IF;

  UPDATE public.prescriptions
  SET status='dispensed',dispensed_by=auth.uid(),dispensed_at=now(),updated_at=now()
  WHERE id=p.prescription_id AND status IN('pending','paid');

  UPDATE public.service_orders
  SET status='completed',completed_at=COALESCE(completed_at,now()),updated_at=now()
  WHERE id=p.service_order_id AND status IN('released','in_progress');

  PERFORM public.record_system_audit(
    'pharmacy_dispensed','pharmacy','pharmacy_dispensing_plans',p.id,'info',
    jsonb_build_object('patient_id',p.patient_id,'prescription_id',p.prescription_id,'inventory_id',p.inventory_id,'quantity',p.prepared_quantity,'dispensed_by',auth.uid(),'dispensed_at',now())
  );

  RETURN jsonb_build_object('plan_id',p.id,'status','dispensed','dispensed_by',auth.uid(),'idempotent',false);
END;
$$;

REVOKE ALL ON FUNCTION public.transition_medication_administration(UUID,TEXT,TEXT,TEXT,UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.reopen_medication_administration(UUID,TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.confirm_pharmacy_dispense(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.transition_medication_administration(UUID,TEXT,TEXT,TEXT,UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reopen_medication_administration(UUID,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.confirm_pharmacy_dispense(UUID) TO authenticated;
REVOKE INSERT,UPDATE,DELETE ON TABLE public.medication_administrations,public.pharmacy_dispensing_plans,public.pharmacy_pos_sales,public.pharmacy_inventory FROM authenticated;

COMMENT ON FUNCTION public.transition_medication_administration(UUID,TEXT,TEXT,TEXT,UUID) IS 'Server-authoritative medication lifecycle with row locking, reason/witness controls, timing guard and audit.';
COMMENT ON FUNCTION public.confirm_pharmacy_dispense(UUID) IS 'Server-authoritative pharmacy dispensing with payment gate, encounter gate, row locking, conditional stock decrement and idempotent terminal response.';
