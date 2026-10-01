BEGIN;

CREATE OR REPLACE FUNCTION public.create_patient_referral_workflow(_patient_id uuid,_destination text,_specialty text DEFAULT NULL::text,_reason text DEFAULT NULL::text,_urgency text DEFAULT 'routine'::text,_clinical_summary text DEFAULT NULL::text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
DECLARE uid uuid:=auth.uid(); v_facility uuid:=public.current_user_facility_id(); v_patient_facility uuid; v_id uuid;
BEGIN
 IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 IF NOT (public.has_role(uid,'admin'::public.app_role) OR public.has_role(uid,'it_admin'::public.app_role) OR public.has_role(uid,'practitioner'::public.app_role) OR public.has_role(uid,'nurse'::public.app_role) OR public.has_role(uid,'midwife'::public.app_role) OR public.has_role(uid,'specialist_nurse'::public.app_role) OR public.has_role(uid,'front_desk'::public.app_role)) THEN RAISE EXCEPTION 'Referral creation is not permitted'; END IF;
 SELECT facility_id INTO v_patient_facility FROM public.patients WHERE id=_patient_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Patient not found'; END IF;
 IF v_patient_facility IS NULL THEN RAISE EXCEPTION 'Patient facility attribution is unresolved'; END IF;
 IF NOT (public.has_role(uid,'admin'::public.app_role) OR public.has_role(uid,'it_admin'::public.app_role)) THEN
   IF v_facility IS NULL THEN RAISE EXCEPTION 'Active facility context is required'; END IF;
   IF v_patient_facility IS DISTINCT FROM v_facility THEN RAISE EXCEPTION 'Patient belongs to a different facility context'; END IF;
 END IF;
 IF NULLIF(pg_catalog.btrim(_destination),'') IS NULL OR NULLIF(pg_catalog.btrim(_reason),'') IS NULL THEN RAISE EXCEPTION 'Destination and reason are required'; END IF;
 IF _urgency NOT IN ('routine','urgent','emergency') THEN RAISE EXCEPTION 'Invalid referral urgency'; END IF;
 INSERT INTO public.patient_referrals(patient_id,destination,specialty,reason,urgency,clinical_summary,referred_by,facility_id)
 VALUES(_patient_id,pg_catalog.btrim(_destination),NULLIF(pg_catalog.btrim(_specialty),''),pg_catalog.btrim(_reason),_urgency,NULLIF(pg_catalog.btrim(_clinical_summary),''),uid,v_patient_facility)
 RETURNING id INTO v_id;
 PERFORM public.record_system_audit('referral_created','care_transitions','patient_referral',v_id,'info',jsonb_build_object('patient_id',_patient_id,'urgency',_urgency,'facility_id',v_patient_facility));
 RETURN jsonb_build_object('referral_id',v_id,'status','requested');
END;$function$;

CREATE OR REPLACE FUNCTION public.schedule_patient_referral_workflow(_referral_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
DECLARE uid uuid:=auth.uid(); v_facility uuid:=public.current_user_facility_id(); r public.patient_referrals%ROWTYPE; v_patient_facility uuid; existing uuid; aid uuid; dept text;
BEGIN
 IF uid IS NULL OR NOT(public.has_role(uid,'admin'::public.app_role) OR public.has_role(uid,'it_admin'::public.app_role) OR public.has_role(uid,'practitioner'::public.app_role) OR public.has_role(uid,'nurse'::public.app_role) OR public.has_role(uid,'midwife'::public.app_role) OR public.has_role(uid,'specialist_nurse'::public.app_role) OR public.has_role(uid,'front_desk'::public.app_role)) THEN RAISE EXCEPTION 'Referral scheduling is not permitted'; END IF;
 SELECT * INTO r FROM public.patient_referrals WHERE id=_referral_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Referral not found'; END IF;
 SELECT facility_id INTO v_patient_facility FROM public.patients WHERE id=r.patient_id FOR UPDATE;
 IF v_patient_facility IS NULL THEN RAISE EXCEPTION 'Patient facility attribution is unresolved'; END IF;
 IF r.facility_id IS NULL THEN RAISE EXCEPTION 'Referral facility attribution is unresolved'; END IF;
 IF r.facility_id IS DISTINCT FROM v_patient_facility THEN RAISE EXCEPTION 'Referral and patient facility context do not match'; END IF;
 IF NOT(public.has_role(uid,'admin'::public.app_role) OR public.has_role(uid,'it_admin'::public.app_role)) THEN
   IF v_facility IS NULL THEN RAISE EXCEPTION 'Active facility context is required'; END IF;
   IF v_patient_facility IS DISTINCT FROM v_facility THEN RAISE EXCEPTION 'Patient belongs to a different facility context'; END IF;
 END IF;
 IF r.status NOT IN('requested','accepted') THEN RAISE EXCEPTION 'Referral is not awaiting scheduling'; END IF;
 IF r.appointment_date IS NULL OR r.appointment_date < now() THEN RAISE EXCEPTION 'A future specialist appointment date is required'; END IF;
 dept:=COALESCE(NULLIF(pg_catalog.btrim(r.specialty),''),NULLIF(pg_catalog.btrim(r.destination),''),'specialist');
 PERFORM pg_advisory_xact_lock(hashtextextended(r.patient_id::text||'|'||r.appointment_date::text||'|'||dept,0));
 SELECT a.id INTO existing FROM public.appointments a WHERE a.patient_id=r.patient_id AND a.scheduled_at=r.appointment_date AND COALESCE(a.department,'')=dept AND COALESCE(a.reason,'')=COALESCE(r.reason,'') AND a.status NOT IN('cancelled','no_show') ORDER BY a.created_at DESC LIMIT 1;
 IF existing IS NULL THEN SELECT id INTO aid FROM public.create_appointment_workflow(r.patient_id,r.appointment_date,dept,r.reason); ELSE aid:=existing; END IF;
 UPDATE public.patient_referrals SET status='scheduled',updated_at=now() WHERE id=r.id;
 PERFORM public.record_system_audit('referral_scheduled','care_transitions','patient_referral',r.id,'info',jsonb_build_object('patient_id',r.patient_id,'appointment_id',aid,'appointment_date',r.appointment_date,'facility_id',v_patient_facility));
 RETURN jsonb_build_object('referral_id',r.id,'status','scheduled','appointment_id',aid,'appointment_date',r.appointment_date);
END;$function$;

REVOKE ALL ON FUNCTION public.create_patient_referral_workflow(uuid,text,text,text,text,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.create_patient_referral_workflow(uuid,text,text,text,text,text) TO authenticated;
REVOKE ALL ON FUNCTION public.schedule_patient_referral_workflow(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.schedule_patient_referral_workflow(uuid) TO authenticated;

COMMIT;