-- Harden referral scheduling and nursing handover lifecycle integrity.
CREATE OR REPLACE FUNCTION public.schedule_patient_referral_workflow(_referral_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE uid UUID:=auth.uid(); r public.patient_referrals%ROWTYPE; existing UUID; aid UUID; dept TEXT;
BEGIN
 IF uid IS NULL OR NOT(public.has_role(uid,'admin') OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse') OR public.has_role(uid,'midwife') OR public.has_role(uid,'specialist_nurse') OR public.has_role(uid,'front_desk')) THEN RAISE EXCEPTION 'Referral scheduling is not permitted'; END IF;
 SELECT * INTO r FROM public.patient_referrals WHERE id=_referral_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Referral not found'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.patients WHERE id=r.patient_id) THEN RAISE EXCEPTION 'Referral patient not found'; END IF;
 IF r.status NOT IN('requested','accepted') THEN RAISE EXCEPTION 'Referral is not awaiting scheduling'; END IF;
 IF r.appointment_date IS NULL OR r.appointment_date < now() THEN RAISE EXCEPTION 'A future specialist appointment date is required'; END IF;
 dept:=COALESCE(NULLIF(btrim(r.specialty),''),NULLIF(btrim(r.destination),''),'specialist');
 PERFORM pg_advisory_xact_lock(hashtextextended(r.patient_id::text||'|'||r.appointment_date::text||'|'||dept,0));
 SELECT a.id INTO existing FROM public.appointments a WHERE a.patient_id=r.patient_id AND a.scheduled_at=r.appointment_date AND COALESCE(a.department,'')=dept AND COALESCE(a.reason,'')=COALESCE(r.reason,'') AND a.status NOT IN('cancelled','no_show') ORDER BY a.created_at DESC LIMIT 1;
 IF existing IS NULL THEN
   SELECT id INTO aid FROM public.create_appointment_workflow(r.patient_id,r.appointment_date,dept,r.reason);
 ELSE aid:=existing; END IF;
 UPDATE public.patient_referrals SET status='scheduled',updated_at=now() WHERE id=r.id;
 PERFORM public.record_system_audit('referral_scheduled','care_transitions','patient_referral',r.id,'info',jsonb_build_object('patient_id',r.patient_id,'appointment_id',aid,'appointment_date',r.appointment_date));
 RETURN jsonb_build_object('referral_id',r.id,'status','scheduled','appointment_id',aid,'appointment_date',r.appointment_date);
END; $$;

CREATE OR REPLACE FUNCTION public.create_nursing_shift_handover(
 _patient_id UUID,_shift_label TEXT,_clinical_summary TEXT,_pending_tasks TEXT DEFAULT NULL,
 _safety_concerns TEXT DEFAULT NULL,_escalation_required BOOLEAN DEFAULT FALSE,_ward_id UUID DEFAULT NULL
) RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE uid UUID:=auth.uid(); id UUID;
BEGIN
 IF uid IS NULL OR NOT(public.has_role(uid,'admin') OR public.has_role(uid,'nurse') OR public.has_role(uid,'midwife') OR public.has_role(uid,'specialist_nurse')) THEN RAISE EXCEPTION 'Nursing role required'; END IF;
 IF _patient_id IS NULL OR NOT EXISTS(SELECT 1 FROM public.patients WHERE id=_patient_id) THEN RAISE EXCEPTION 'Patient not found'; END IF;
 IF NULLIF(btrim(_clinical_summary),'') IS NULL THEN RAISE EXCEPTION 'Clinical summary is required'; END IF;
 IF _ward_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.ward_units WHERE id=_ward_id) THEN RAISE EXCEPTION 'Ward not found'; END IF;
 IF EXISTS(SELECT 1 FROM public.nursing_shift_handovers WHERE patient_id=_patient_id AND shift_label=COALESCE(NULLIF(btrim(_shift_label),''),'unspecified') AND acknowledged_at IS NULL) THEN RAISE EXCEPTION 'An open handover already exists for this patient and shift'; END IF;
 INSERT INTO public.nursing_shift_handovers(patient_id,ward_id,outgoing_officer,shift_label,clinical_summary,pending_tasks,safety_concerns,escalation_required)
 VALUES(_patient_id,_ward_id,uid,COALESCE(NULLIF(btrim(_shift_label),''),'unspecified'),btrim(_clinical_summary),NULLIF(btrim(_pending_tasks),''),NULLIF(btrim(_safety_concerns),''),COALESCE(_escalation_required,false))
 RETURNING id INTO id;
 RETURN id;
END; $$;

CREATE OR REPLACE FUNCTION public.acknowledge_nursing_handover(_handover_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE uid UUID:=auth.uid(); h public.nursing_shift_handovers%ROWTYPE;
BEGIN
 IF uid IS NULL OR NOT(public.has_role(uid,'admin') OR public.has_role(uid,'nurse') OR public.has_role(uid,'midwife') OR public.has_role(uid,'specialist_nurse')) THEN RAISE EXCEPTION 'Nursing role required'; END IF;
 SELECT * INTO h FROM public.nursing_shift_handovers WHERE id=_handover_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Handover not found'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.patients WHERE id=h.patient_id) THEN RAISE EXCEPTION 'Handover patient not found'; END IF;
 IF h.acknowledged_at IS NOT NULL THEN RETURN jsonb_build_object('handover_id',h.id,'acknowledged_at',h.acknowledged_at,'acknowledged_by',h.incoming_officer); END IF;
 IF h.outgoing_officer=uid THEN RAISE EXCEPTION 'Outgoing officer cannot acknowledge their own handover'; END IF;
 UPDATE public.nursing_shift_handovers SET incoming_officer=uid,acknowledged_at=now() WHERE id=h.id;
 PERFORM public.record_system_audit('nursing_handover_acknowledged','clinical','nursing_shift_handovers',h.id,'info',jsonb_build_object('patient_id',h.patient_id,'incoming_officer',uid));
 RETURN jsonb_build_object('handover_id',h.id,'acknowledged_at',now(),'acknowledged_by',uid);
END; $$;

REVOKE ALL ON FUNCTION public.schedule_patient_referral_workflow(UUID) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.create_nursing_shift_handover(UUID,TEXT,TEXT,TEXT,TEXT,BOOLEAN,UUID) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.acknowledge_nursing_handover(UUID) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.schedule_patient_referral_workflow(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_nursing_shift_handover(UUID,TEXT,TEXT,TEXT,TEXT,BOOLEAN,UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.acknowledge_nursing_handover(UUID) TO authenticated;
