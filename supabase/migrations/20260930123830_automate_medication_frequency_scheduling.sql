-- Deterministic MAR scheduling for explicit frequency intervals.
-- Ghana MOH guidance documents BD as 12-hourly and TDS as 8-hourly; the UI should prefer explicit hourly instructions where available.
CREATE OR REPLACE FUNCTION public.medication_frequency_interval(_frequency text)
RETURNS interval LANGUAGE sql IMMUTABLE SET search_path='' AS $$
SELECT CASE
WHEN regexp_replace(lower(coalesce(_frequency,'')),'[[:space:]._-]+','','g') IN ('bd','bid','12hourly','q12h','q12hourly','every12hours','twicedaily') THEN interval '12 hours'
WHEN regexp_replace(lower(coalesce(_frequency,'')),'[[:space:]._-]+','','g') IN ('tds','tid','8hourly','q8h','q8hourly','every8hours','thricedaily') THEN interval '8 hours'
WHEN regexp_replace(lower(coalesce(_frequency,'')),'[[:space:]._-]+','','g') IN ('qid','qds','6hourly','q6h','q6hourly','every6hours','fourtimesdaily') THEN interval '6 hours'
WHEN regexp_replace(lower(coalesce(_frequency,'')),'[[:space:]._-]+','','g') IN ('q4h','q4hourly','4hourly','every4hours') THEN interval '4 hours'
WHEN regexp_replace(lower(coalesce(_frequency,'')),'[[:space:]._-]+','','g') IN ('q24h','q24hourly','24hourly','daily','od','onceaday','oncedaily') THEN interval '24 hours'
WHEN lower(coalesce(_frequency,'')) ~ 'every[[:space:]]*[0-9]+[[:space:]]*hours?' THEN make_interval(hours=>(regexp_match(lower(_frequency),'every[[:space:]]*([0-9]+)[[:space:]]*hours?'))[1]::integer)
WHEN lower(coalesce(_frequency,'')) ~ '[0-9]+[[:space:]]*hourly' THEN make_interval(hours=>(regexp_match(lower(_frequency),'([0-9]+)[[:space:]]*hourly'))[1]::integer)
ELSE NULL END $$;
CREATE OR REPLACE FUNCTION public.prescription_duration_end(_created_at timestamptz,_duration text)
RETURNS timestamptz LANGUAGE sql IMMUTABLE SET search_path='' AS $$
SELECT CASE
WHEN _created_at IS NULL OR nullif(btrim(coalesce(_duration,'')),'') IS NULL THEN NULL
WHEN lower(_duration) ~ '([0-9]+)[[:space:]]*(day|days|d)' THEN _created_at+make_interval(days=>(regexp_match(lower(_duration),'([0-9]+)[[:space:]]*(?:day|days|d)'))[1]::integer)
WHEN lower(_duration) ~ '([0-9]+)[[:space:]]*(week|weeks|wk|w)' THEN _created_at+make_interval(days=>((regexp_match(lower(_duration),'([0-9]+)[[:space:]]*(?:week|weeks|wk|w)'))[1]::integer)*7)
WHEN lower(_duration) ~ '([0-9]+)[[:space:]]*(hour|hours|hr|h)' THEN _created_at+make_interval(hours=>(regexp_match(lower(_duration),'([0-9]+)[[:space:]]*(?:hour|hours|hr|h)'))[1]::integer)
ELSE NULL END $$;
CREATE OR REPLACE FUNCTION public.create_initial_medication_administration()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_interval interval;
BEGIN
IF NEW.status IN ('cancelled','voided') THEN RETURN NEW; END IF;
v_interval:=public.medication_frequency_interval(NEW.frequency);
IF v_interval IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.medication_administrations ma WHERE ma.prescription_id=NEW.id) THEN
INSERT INTO public.medication_administrations(patient_id,prescription_id,medication_name,dose,route,scheduled_at,notes,due_window_minutes,facility_id)
VALUES(NEW.patient_id,NEW.id,coalesce(nullif(btrim(NEW.medication_name),''),btrim(NEW.medication)),NEW.dosage,NEW.route,now(),
  'Automatically scheduled from prescription frequency '||NEW.frequency,30,NEW.facility_id);
END IF; RETURN NEW; END; $$;
DROP TRIGGER IF EXISTS trg_create_initial_medication_administration ON public.prescriptions;
CREATE TRIGGER trg_create_initial_medication_administration AFTER INSERT ON public.prescriptions FOR EACH ROW EXECUTE FUNCTION public.create_initial_medication_administration();
CREATE OR REPLACE FUNCTION public.transition_medication_administration(_record_id uuid,_status text,_reason text DEFAULT NULL,_notes text DEFAULT NULL,_witnessed_by uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $function$
DECLARE r public.medication_administrations%ROWTYPE; p public.prescriptions%ROWTYPE; uid uuid:=auth.uid(); overdue boolean; v_interval interval; v_next timestamptz; v_end timestamptz;
BEGIN
IF uid IS NULL OR NOT(public.has_role(uid,'admin') OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse') OR public.has_role(uid,'midwife') OR public.has_role(uid,'specialist_nurse') OR public.has_role(uid,'pharmacist')) THEN RAISE EXCEPTION 'Authorised clinical role required'; END IF;
IF _status NOT IN('administered','held','refused','omitted','not_given','cancelled') THEN RAISE EXCEPTION 'Unsupported medication administration status'; END IF;
SELECT * INTO r FROM public.medication_administrations WHERE id=_record_id FOR UPDATE; IF NOT FOUND THEN RAISE EXCEPTION 'Medication administration record not found'; END IF;
IF r.patient_id IS NULL OR NOT EXISTS(SELECT 1 FROM public.patients WHERE id=r.patient_id AND coalesce(status,'active')<>'inactive') THEN RAISE EXCEPTION 'Medication patient not found or inactive'; END IF;
IF r.prescription_id IS NOT NULL THEN SELECT * INTO p FROM public.prescriptions WHERE id=r.prescription_id FOR UPDATE; IF NOT FOUND OR p.patient_id<>r.patient_id THEN RAISE EXCEPTION 'Medication prescription does not match patient'; END IF; IF p.status IN('cancelled','voided') THEN RAISE EXCEPTION 'Cannot administer a cancelled prescription'; END IF; END IF;
overdue:=r.scheduled_at IS NOT NULL AND now()>r.scheduled_at+make_interval(mins=>r.due_window_minutes);
IF _status='administered' AND r.locked_at IS NOT NULL THEN RAISE EXCEPTION 'Medication slot is locked. An authorised reopening with explanation is required.'; END IF;
IF _status IN('held','refused','omitted','not_given') AND r.locked_at IS NULL AND overdue THEN UPDATE public.medication_administrations SET locked_at=now(),lock_reason=coalesce(_reason,'Late medication event requires explanation'),updated_at=now() WHERE id=_record_id; RAISE EXCEPTION 'Medication slot has elapsed. Reopen it with an authorised explanation before documenting the event.'; END IF;
IF _status='administered' THEN
UPDATE public.medication_administrations SET status='administered',administered_at=now(),administered_by=uid,witnessed_by=coalesce(_witnessed_by,witnessed_by),reason=nullif(pg_catalog.btrim(coalesce(_reason,'')),''),notes=coalesce(_notes,notes),updated_at=now() WHERE id=_record_id RETURNING * INTO r;
IF r.prescription_id IS NOT NULL THEN
v_interval:=public.medication_frequency_interval(p.frequency); v_end:=public.prescription_duration_end(p.created_at,p.duration); v_next:=now()+v_interval;
IF v_interval IS NOT NULL AND (v_end IS NULL OR v_next<v_end) AND NOT EXISTS(SELECT 1 FROM public.medication_administrations ma WHERE ma.prescription_id=r.prescription_id AND ma.scheduled_at=v_next) THEN
INSERT INTO public.medication_administrations(patient_id,prescription_id,medication_name,dose,route,scheduled_at,notes,due_window_minutes,facility_id)
VALUES(r.patient_id,r.prescription_id,coalesce(nullif(btrim(p.medication_name),''),btrim(p.medication)),p.dosage,p.route,v_next,'Automatically scheduled after documented administration',r.due_window_minutes,r.facility_id);
END IF; END IF;
ELSE
UPDATE public.medication_administrations SET status=_status,reason=nullif(pg_catalog.btrim(coalesce(_reason,'')),''),notes=coalesce(_notes,notes),updated_at=now() WHERE id=_record_id RETURNING * INTO r;
END IF;
PERFORM public.record_system_audit('medication_administration_'||_status,'clinical','medication_administrations',_record_id,CASE WHEN _status='administered' THEN 'info' ELSE 'warning' END,jsonb_build_object('record_id',_record_id,'patient_id',r.patient_id,'prescription_id',r.prescription_id,'administered_by',uid,'timestamp',now(),'reason',r.reason,'witnessed_by',r.witnessed_by,'next_scheduled_at',v_next));
RETURN jsonb_build_object('id',r.id,'status',r.status,'administered_by',r.administered_by,'administered_at',r.administered_at,'next_scheduled_at',v_next);
END; $function$;
REVOKE ALL ON FUNCTION public.medication_frequency_interval(text) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.prescription_duration_end(timestamptz,text) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.create_initial_medication_administration() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.transition_medication_administration(uuid,text,text,text,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.transition_medication_administration(uuid,text,text,text,uuid) TO authenticated;
