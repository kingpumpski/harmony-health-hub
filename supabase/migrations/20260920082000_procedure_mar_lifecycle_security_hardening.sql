-- Harden procedure and medication administration lifecycle authorization.
CREATE OR REPLACE FUNCTION public.create_procedure_note(
  _patient_id UUID,_procedure_name TEXT,_template_used TEXT,_indication TEXT,_technique TEXT,
  _findings TEXT,_complications TEXT,_post_op_plan TEXT,_charge_amount NUMERIC,_service_order_id UUID
)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE uid UUID:=auth.uid(); sid public.service_orders%ROWTYPE; id UUID;
BEGIN
 IF uid IS NULL OR NOT(public.has_role(uid,'admin') OR public.has_role(uid,'practitioner') OR public.has_role(uid,'specialist_nurse') OR public.has_role(uid,'nurse') OR public.has_role(uid,'midwife')) THEN RAISE EXCEPTION 'Clinical role required'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.patients WHERE id=_patient_id) THEN RAISE EXCEPTION 'Patient not found'; END IF;
 IF COALESCE(_charge_amount,0)<0 THEN RAISE EXCEPTION 'Charge amount cannot be negative'; END IF;
 IF COALESCE(_charge_amount,0)>0 THEN
   IF _service_order_id IS NULL THEN RAISE EXCEPTION 'A released service order is required for a chargeable procedure'; END IF;
   SELECT * INTO sid FROM public.service_orders WHERE id=_service_order_id FOR UPDATE;
   IF NOT FOUND OR sid.patient_id<>_patient_id OR sid.department<>'procedure' OR sid.related_entity_id IS NOT NULL AND sid.related_entity_id<>_service_order_id THEN RAISE EXCEPTION 'Procedure service order linkage is invalid'; END IF;
   IF sid.status NOT IN('released','in_progress','completed') THEN RAISE EXCEPTION 'Procedure payment has not been released'; END IF;
 END IF;
 INSERT INTO public.procedure_notes(patient_id,procedure_name,template_used,indication,technique,findings,complications,post_op_plan,performed_by,status,charge_amount,service_order_id)
 VALUES(_patient_id,NULLIF(btrim(_procedure_name),''),NULLIF(btrim(_template_used),''),NULLIF(btrim(_indication),''),NULLIF(btrim(_technique),''),NULLIF(btrim(_findings),''),NULLIF(btrim(_complications),''),NULLIF(btrim(_post_op_plan),''),uid,'completed',COALESCE(_charge_amount,0),_service_order_id)
 RETURNING id INTO id;
 RETURN id;
END; $$;

CREATE OR REPLACE FUNCTION public.transition_medication_administration(
  _record_id UUID,_status TEXT,_reason TEXT DEFAULT NULL,_notes TEXT DEFAULT NULL,_witnessed_by UUID DEFAULT NULL
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE r public.medication_administrations%ROWTYPE; p public.prescriptions%ROWTYPE; i public.pharmacy_inventory%ROWTYPE; uid UUID:=auth.uid(); overdue BOOLEAN; order_status TEXT;
BEGIN
 IF uid IS NULL OR NOT(public.has_role(uid,'admin') OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse') OR public.has_role(uid,'midwife') OR public.has_role(uid,'specialist_nurse') OR public.has_role(uid,'pharmacist')) THEN RAISE EXCEPTION 'Authorised clinical role required'; END IF;
 IF _status NOT IN('administered','held','refused','omitted','not_given','cancelled') THEN RAISE EXCEPTION 'Unsupported medication administration status'; END IF;
 SELECT * INTO r FROM public.medication_administrations WHERE id=_record_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Medication administration record not found'; END IF;
 IF r.patient_id IS NULL THEN RAISE EXCEPTION 'Medication administration has no patient'; END IF;
 IF r.prescription_id IS NOT NULL THEN
   SELECT * INTO p FROM public.prescriptions WHERE id=r.prescription_id FOR UPDATE;
   IF NOT FOUND OR p.patient_id<>r.patient_id THEN RAISE EXCEPTION 'Medication prescription does not match patient'; END IF;
   IF p.status IN('cancelled','voided') THEN RAISE EXCEPTION 'Cannot administer a cancelled prescription'; END IF;
 END IF;
 overdue:=r.scheduled_at IS NOT NULL AND now()>r.scheduled_at+make_interval(mins=>r.due_window_minutes);
 IF _status='administered' AND r.locked_at IS NOT NULL THEN RAISE EXCEPTION 'Medication slot is locked. An authorised reopening with explanation is required.'; END IF;
 IF _status IN('held','refused','omitted','not_given') AND r.locked_at IS NULL AND overdue THEN
   UPDATE public.medication_administrations SET locked_at=now(),lock_reason=COALESCE(_reason,'Late medication event requires explanation'),updated_at=now() WHERE id=_record_id;
   RAISE EXCEPTION 'Medication slot has elapsed. Reopen it with an authorised explanation before documenting the event.';
 END IF;
 IF _status='administered' THEN
   IF r.inventory_id IS NOT NULL THEN
     SELECT * INTO i FROM public.pharmacy_inventory WHERE id=r.inventory_id FOR UPDATE;
     IF NOT FOUND OR NOT i.active THEN RAISE EXCEPTION 'Medication inventory item is unavailable'; END IF;
   END IF;
   UPDATE public.medication_administrations SET status='administered',administered_at=now(),administered_by=uid,witnessed_by=COALESCE(_witnessed_by,witnessed_by),reason=_reason,notes=COALESCE(_notes,notes),updated_at=now() WHERE id=_record_id;
 ELSE
   UPDATE public.medication_administrations SET status=_status,reason=_reason,notes=COALESCE(_notes,notes),updated_at=now() WHERE id=_record_id;
 END IF;
 PERFORM public.record_system_audit('medication_administration_'||_status,'clinical','medication_administrations',_record_id,CASE WHEN _status='administered' THEN 'info' ELSE 'warning' END,jsonb_build_object('record_id',_record_id,'patient_id',r.patient_id,'administered_by',uid,'timestamp',now(),'reason',_reason,'witnessed_by',_witnessed_by));
 RETURN jsonb_build_object('id',_record_id,'status',_status,'administered_by',uid,'administered_at',CASE WHEN _status='administered' THEN now() ELSE r.administered_at END);
END; $$;

REVOKE ALL ON FUNCTION public.create_procedure_note(UUID,TEXT,TEXT,TEXT,TEXT,TEXT,TEXT,TEXT,NUMERIC,UUID) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.transition_medication_administration(UUID,TEXT,TEXT,TEXT,UUID) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.create_procedure_note(UUID,TEXT,TEXT,TEXT,TEXT,TEXT,TEXT,TEXT,NUMERIC,UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.transition_medication_administration(UUID,TEXT,TEXT,TEXT,UUID) TO authenticated;
