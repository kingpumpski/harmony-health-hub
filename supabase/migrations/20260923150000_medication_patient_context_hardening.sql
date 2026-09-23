-- Strengthen MAR scheduling context without changing the established RPC contract.
CREATE OR REPLACE FUNCTION public.schedule_medication_administration(
  _patient_id UUID,_medication_name TEXT,_dose TEXT DEFAULT NULL,_route TEXT DEFAULT NULL,
  _scheduled_at TIMESTAMPTZ DEFAULT NULL,_notes TEXT DEFAULT NULL,_due_window_minutes INTEGER DEFAULT 30
)
RETURNS public.medication_administrations
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public
AS $$
DECLARE r public.medication_administrations;
BEGIN
 IF auth.uid() IS NULL OR NOT(public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife') OR public.has_role(auth.uid(),'specialist_nurse')) THEN RAISE EXCEPTION 'Clinical role required'; END IF;
 IF _patient_id IS NULL OR NOT EXISTS(SELECT 1 FROM public.patients WHERE id=_patient_id AND COALESCE(status,'active')<>'inactive') THEN RAISE EXCEPTION 'Patient not found or inactive'; END IF;
 IF length(trim(COALESCE(_medication_name,'')))<2 THEN RAISE EXCEPTION 'Medication name is required'; END IF;
 IF _scheduled_at IS NOT NULL AND _scheduled_at < now()-interval '24 hours' THEN RAISE EXCEPTION 'Medication schedule is outside the permitted window'; END IF;
 INSERT INTO public.medication_administrations(patient_id,medication_name,dose,route,scheduled_at,notes,due_window_minutes)
 VALUES(_patient_id,trim(_medication_name),NULLIF(trim(COALESCE(_dose,'')),''),NULLIF(trim(COALESCE(_route,'')),''),_scheduled_at,_notes,LEAST(GREATEST(COALESCE(_due_window_minutes,30),5),240))
 RETURNING * INTO r;
 PERFORM public.record_system_audit('medication_scheduled','clinical','medication_administrations',r.id,'info',jsonb_build_object('patient_id',r.patient_id,'scheduled_at',r.scheduled_at,'actor_id',auth.uid()));
 RETURN r;
END;
$$;

CREATE OR REPLACE FUNCTION public.transition_medication_administration(
  _record_id UUID,_status TEXT,_reason TEXT DEFAULT NULL,_notes TEXT DEFAULT NULL,_witnessed_by UUID DEFAULT NULL
)
RETURNS public.medication_administrations
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public
AS $$
DECLARE r public.medication_administrations; p public.prescriptions%ROWTYPE; uid UUID:=auth.uid();
BEGIN
 IF uid IS NULL OR NOT(public.has_role(uid,'admin') OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse') OR public.has_role(uid,'midwife') OR public.has_role(uid,'specialist_nurse') OR public.has_role(uid,'pharmacist')) THEN RAISE EXCEPTION 'Authorised clinical role required'; END IF;
 IF _status NOT IN('administered','held','refused','omitted','not_given','cancelled') THEN RAISE EXCEPTION 'Unsupported medication administration status'; END IF;
 SELECT * INTO r FROM public.medication_administrations WHERE id=_record_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Medication administration record not found'; END IF;
 IF r.patient_id IS NULL OR NOT EXISTS(SELECT 1 FROM public.patients WHERE id=r.patient_id AND COALESCE(status,'active')<>'inactive') THEN RAISE EXCEPTION 'Medication patient not found or inactive'; END IF;
 IF r.prescription_id IS NOT NULL THEN
  SELECT * INTO p FROM public.prescriptions WHERE id=r.prescription_id FOR UPDATE;
  IF NOT FOUND OR p.patient_id<>r.patient_id THEN RAISE EXCEPTION 'Medication prescription does not match patient'; END IF;
  IF p.status IN('cancelled','voided') THEN RAISE EXCEPTION 'Cannot administer a cancelled prescription'; END IF;
 END IF;
 IF r.locked_at IS NOT NULL THEN RAISE EXCEPTION 'Medication slot is locked; provide an authorised reopening explanation first'; END IF;
 IF r.status<>'scheduled' THEN RAISE EXCEPTION 'Medication slot has already been documented'; END IF;
 UPDATE public.medication_administrations
 SET status=_status,reason=NULLIF(trim(COALESCE(_reason,'')),''),notes=COALESCE(_notes,notes),
 administered_by=CASE WHEN _status='administered' THEN uid ELSE administered_by END,
 administered_at=CASE WHEN _status='administered' THEN now() ELSE administered_at END,
 witnessed_by=CASE WHEN _status='administered' THEN _witnessed_by ELSE witnessed_by END,updated_at=now()
 WHERE id=_record_id RETURNING * INTO r;
 PERFORM public.record_system_audit('medication_'||_status,'clinical','medication_administrations',r.id,'info',jsonb_build_object('patient_id',r.patient_id,'status',r.status,'administered_by',r.administered_by,'administered_at',r.administered_at,'reason',r.reason));
 RETURN r;
END;
$$;

REVOKE ALL ON FUNCTION public.schedule_medication_administration(UUID,TEXT,TEXT,TEXT,TIMESTAMPTZ,TEXT,INTEGER) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.transition_medication_administration(UUID,TEXT,TEXT,TEXT,UUID) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.schedule_medication_administration(UUID,TEXT,TEXT,TEXT,TIMESTAMPTZ,TEXT,INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.transition_medication_administration(UUID,TEXT,TEXT,TEXT,UUID) TO authenticated;
