-- Reconcile missing creation RPC contracts and strengthen auditability.
-- Additive: uses existing global HIMS tables.

CREATE OR REPLACE FUNCTION public.create_emergency_case(
  _patient_id UUID,
  _chief_complaint TEXT,
  _acuity TEXT DEFAULT 'urgent',
  _arrival_mode TEXT DEFAULT 'walk_in',
  _assigned_officer UUID DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE uid UUID := auth.uid(); v_id UUID; v_officer UUID;
BEGIN
  IF uid IS NULL OR NOT (public.has_role(uid,'admin') OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse') OR public.has_role(uid,'specialist_nurse') OR public.has_role(uid,'front_desk')) THEN
    RAISE EXCEPTION 'Emergency workflow role required';
  END IF;
  IF _patient_id IS NULL THEN RAISE EXCEPTION 'Patient is required'; END IF;
  IF NULLIF(trim(_chief_complaint),'') IS NULL THEN RAISE EXCEPTION 'Chief complaint is required'; END IF;
  IF _acuity NOT IN ('resuscitation','emergency','urgent','less_urgent','non_urgent') THEN RAISE EXCEPTION 'Invalid emergency acuity'; END IF;
  IF _arrival_mode NOT IN ('walk_in','ambulance','referral','other') THEN RAISE EXCEPTION 'Invalid arrival mode'; END IF;
  v_officer := CASE WHEN _assigned_officer = uid THEN uid ELSE NULL END;
  IF _assigned_officer IS NOT NULL AND _assigned_officer <> uid AND NOT public.has_role(uid,'admin') THEN
    RAISE EXCEPTION 'Users may only assign emergency cases to themselves';
  END IF;
  INSERT INTO public.emergency_cases(patient_id,chief_complaint,acuity,arrival_mode,assigned_officer,status)
  VALUES (_patient_id,trim(_chief_complaint),_acuity,_arrival_mode,v_officer,'waiting') RETURNING id INTO v_id;
  PERFORM public.record_system_audit('emergency_case_created','emergency','emergency_case',v_id,'info',jsonb_build_object('patient_id',_patient_id,'acuity',_acuity,'arrival_mode',_arrival_mode));
  RETURN v_id;
END; $$;

CREATE OR REPLACE FUNCTION public.create_insurance_claim_draft(
  _patient_id UUID,
  _payer_name TEXT,
  _member_number TEXT DEFAULT NULL,
  _amount_claimed NUMERIC DEFAULT 0,
  _invoice_id UUID DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE uid UUID := auth.uid(); v_id UUID;
BEGIN
  IF uid IS NULL OR NOT (public.has_role(uid,'admin') OR public.has_role(uid,'accountant') OR public.has_role(uid,'practitioner')) THEN
    RAISE EXCEPTION 'Claims role required';
  END IF;
  IF _patient_id IS NULL OR NULLIF(trim(_payer_name),'') IS NULL THEN RAISE EXCEPTION 'Patient and payer are required'; END IF;
  IF COALESCE(_amount_claimed,0) < 0 THEN RAISE EXCEPTION 'Claim amount cannot be negative'; END IF;
  INSERT INTO public.insurance_claims(patient_id,invoice_id,payer_name,member_number,amount_claimed,status,created_by)
  VALUES (_patient_id,_invoice_id,trim(_payer_name),NULLIF(trim(_member_number),''),COALESCE(_amount_claimed,0),'draft',uid) RETURNING id INTO v_id;
  INSERT INTO public.insurance_claim_events(claim_id,event_type,to_status,notes,actor_id)
  VALUES (v_id,'claim_created','draft','Initial claim draft created',uid);
  PERFORM public.record_system_audit('insurance_claim_created','insurance','insurance_claim',v_id,'info',jsonb_build_object('patient_id',_patient_id,'amount_claimed',COALESCE(_amount_claimed,0)));
  RETURN v_id;
END; $$;

CREATE OR REPLACE FUNCTION public.assign_ward_bed(_bed_id UUID, _patient_id UUID, _admission_id UUID DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE b public.ward_beds%ROWTYPE; uid UUID := auth.uid();
BEGIN
  IF uid IS NULL OR NOT (public.has_role(uid,'admin') OR public.has_role(uid,'nurse') OR public.has_role(uid,'specialist_nurse')) THEN RAISE EXCEPTION 'Nursing role required'; END IF;
  IF _patient_id IS NULL OR NOT EXISTS (SELECT 1 FROM public.patients WHERE id=_patient_id) THEN RAISE EXCEPTION 'Patient not found'; END IF;
  SELECT * INTO b FROM public.ward_beds WHERE id=_bed_id FOR UPDATE;
  IF b.id IS NULL THEN RAISE EXCEPTION 'Bed not found'; END IF;
  IF b.status <> 'available' OR b.patient_id IS NOT NULL THEN RAISE EXCEPTION 'Bed is not available'; END IF;
  UPDATE public.ward_beds SET patient_id=_patient_id,admission_id=_admission_id,status='occupied',occupied_at=now(),released_at=NULL WHERE id=_bed_id;
  PERFORM public.record_system_audit('ward_bed_assigned','inpatient','ward_bed',_bed_id,'info',jsonb_build_object('patient_id',_patient_id,'admission_id',_admission_id));
  RETURN jsonb_build_object('bed_id',_bed_id,'status','occupied','patient_id',_patient_id);
END; $$;

CREATE OR REPLACE FUNCTION public.create_theatre_case(
  _patient_id UUID,
  _procedure_name TEXT,
  _scheduled_start TIMESTAMPTZ,
  _theatre_name TEXT DEFAULT NULL,
  _urgency TEXT DEFAULT 'elective',
  _surgeon_id UUID DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE uid UUID := auth.uid(); v_id UUID; v_surgeon UUID;
BEGIN
  IF uid IS NULL OR NOT (public.has_role(uid,'admin') OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse') OR public.has_role(uid,'specialist_nurse')) THEN RAISE EXCEPTION 'Clinical role required'; END IF;
  IF _patient_id IS NULL OR NULLIF(trim(_procedure_name),'') IS NULL OR _scheduled_start IS NULL THEN RAISE EXCEPTION 'Patient, procedure and scheduled start are required'; END IF;
  IF _urgency NOT IN ('emergency','urgent','elective') THEN RAISE EXCEPTION 'Invalid urgency'; END IF;
  IF _surgeon_id IS NOT NULL AND _surgeon_id <> uid AND NOT public.has_role(uid,'admin') THEN RAISE EXCEPTION 'Users may only assign themselves as surgeon'; END IF;
  v_surgeon := COALESCE(_surgeon_id,uid);
  INSERT INTO public.theatre_cases(patient_id,procedure_name,scheduled_start,theatre_name,urgency,surgeon_id,created_by,status)
  VALUES (_patient_id,trim(_procedure_name),_scheduled_start,NULLIF(trim(_theatre_name),''),_urgency,v_surgeon,uid,'scheduled') RETURNING id INTO v_id;
  PERFORM public.record_system_audit('theatre_case_created','theatre','theatre_case',v_id,'info',jsonb_build_object('patient_id',_patient_id,'urgency',_urgency));
  RETURN v_id;
END; $$;

CREATE OR REPLACE FUNCTION public.assign_theatre_anesthetist(_case_id UUID,_anesthetist_id UUID) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE uid UUID := auth.uid();
BEGIN
  IF uid IS NULL OR NOT (public.has_role(uid,'admin') OR public.has_role(uid,'practitioner')) THEN RAISE EXCEPTION 'Clinical administrator role required'; END IF;
  IF _anesthetist_id IS NULL OR NOT EXISTS (SELECT 1 FROM public.profiles WHERE id=_anesthetist_id AND specialization IS NOT NULL AND specialization ILIKE '%anesth%') THEN RAISE EXCEPTION 'Selected officer is not recorded as an anesthetist'; END IF;
  UPDATE public.theatre_cases SET anesthetist_id=_anesthetist_id WHERE id=_case_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Theatre case not found'; END IF;
  PERFORM public.record_system_audit('theatre_anesthetist_assigned','theatre','theatre_case',_case_id,'info',jsonb_build_object('anesthetist_id',_anesthetist_id));
  RETURN jsonb_build_object('case_id',_case_id,'anesthetist_id',_anesthetist_id);
END; $$;

REVOKE ALL ON FUNCTION public.create_emergency_case(UUID,TEXT,TEXT,TEXT,UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_emergency_case(UUID,TEXT,TEXT,TEXT,UUID) TO authenticated;
REVOKE ALL ON FUNCTION public.create_insurance_claim_draft(UUID,TEXT,TEXT,NUMERIC,UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_insurance_claim_draft(UUID,TEXT,TEXT,NUMERIC,UUID) TO authenticated;
REVOKE ALL ON FUNCTION public.assign_ward_bed(UUID,UUID,UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.assign_ward_bed(UUID,UUID,UUID) TO authenticated;
REVOKE ALL ON FUNCTION public.create_theatre_case(UUID,TEXT,TIMESTAMPTZ,TEXT,TEXT,UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_theatre_case(UUID,TEXT,TIMESTAMPTZ,TEXT,TEXT,UUID) TO authenticated;
REVOKE ALL ON FUNCTION public.assign_theatre_anesthetist(UUID,UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.assign_theatre_anesthetist(UUID,UUID) TO authenticated;
