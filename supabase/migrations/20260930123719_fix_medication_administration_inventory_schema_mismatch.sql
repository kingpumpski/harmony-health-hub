-- Fix the production MAR transition function to match the live medication_administrations schema.
-- The live table does not contain inventory_id; pharmacy inventory is not directly linked from MAR rows.
-- Keep medication/prescription validation and lifecycle locking server-authoritative.
CREATE OR REPLACE FUNCTION public.transition_medication_administration(
  _record_id uuid,
  _status text,
  _reason text DEFAULT NULL,
  _notes text DEFAULT NULL,
  _witnessed_by uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  r public.medication_administrations%ROWTYPE;
  p public.prescriptions%ROWTYPE;
  uid uuid := auth.uid();
  overdue boolean;
BEGIN
  IF uid IS NULL OR NOT (
    public.has_role(uid,'admin') OR public.has_role(uid,'practitioner') OR
    public.has_role(uid,'nurse') OR public.has_role(uid,'midwife') OR
    public.has_role(uid,'specialist_nurse') OR public.has_role(uid,'pharmacist')
  ) THEN RAISE EXCEPTION 'Authorised clinical role required'; END IF;
  IF _status NOT IN ('administered','held','refused','omitted','not_given','cancelled') THEN
    RAISE EXCEPTION 'Unsupported medication administration status';
  END IF;
  SELECT * INTO r FROM public.medication_administrations WHERE id=_record_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Medication administration record not found'; END IF;
  IF r.patient_id IS NULL OR NOT EXISTS (SELECT 1 FROM public.patients WHERE id=r.patient_id AND coalesce(status,'active')<>'inactive') THEN
    RAISE EXCEPTION 'Medication patient not found or inactive';
  END IF;
  IF r.prescription_id IS NOT NULL THEN
    SELECT * INTO p FROM public.prescriptions WHERE id=r.prescription_id FOR UPDATE;
    IF NOT FOUND OR p.patient_id<>r.patient_id THEN RAISE EXCEPTION 'Medication prescription does not match patient'; END IF;
    IF p.status IN ('cancelled','voided') THEN RAISE EXCEPTION 'Cannot administer a cancelled prescription'; END IF;
  END IF;
  overdue := r.scheduled_at IS NOT NULL AND now()>r.scheduled_at+make_interval(mins=>r.due_window_minutes);
  IF _status='administered' AND r.locked_at IS NOT NULL THEN
    RAISE EXCEPTION 'Medication slot is locked. An authorised reopening with explanation is required.';
  END IF;
  IF _status IN ('held','refused','omitted','not_given') AND r.locked_at IS NULL AND overdue THEN
    UPDATE public.medication_administrations SET locked_at=now(),lock_reason=coalesce(_reason,'Late medication event requires explanation'),updated_at=now() WHERE id=_record_id;
    RAISE EXCEPTION 'Medication slot has elapsed. Reopen it with an authorised explanation before documenting the event.';
  END IF;
  IF _status='administered' THEN
    UPDATE public.medication_administrations SET status='administered',administered_at=now(),administered_by=uid,
      witnessed_by=coalesce(_witnessed_by,witnessed_by),reason=nullif(pg_catalog.btrim(coalesce(_reason,'')),''),
      notes=coalesce(_notes,notes),updated_at=now() WHERE id=_record_id RETURNING * INTO r;
  ELSE
    UPDATE public.medication_administrations SET status=_status,reason=nullif(pg_catalog.btrim(coalesce(_reason,'')),''),
      notes=coalesce(_notes,notes),updated_at=now() WHERE id=_record_id RETURNING * INTO r;
  END IF;
  PERFORM public.record_system_audit('medication_administration_'||_status,'clinical','medication_administrations',_record_id,
    CASE WHEN _status='administered' THEN 'info' ELSE 'warning' END,
    jsonb_build_object('record_id',_record_id,'patient_id',r.patient_id,'administered_by',uid,'timestamp',now(),'reason',r.reason,'witnessed_by',r.witnessed_by));
  RETURN jsonb_build_object('id',r.id,'status',r.status,'administered_by',r.administered_by,'administered_at',r.administered_at);
END;
$function$;
REVOKE ALL ON FUNCTION public.transition_medication_administration(uuid,text,text,text,uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.transition_medication_administration(uuid,text,text,text,uuid) TO authenticated;
