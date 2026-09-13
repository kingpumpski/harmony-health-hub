-- Close remaining direct-write gaps in emergency and insurance intake.
CREATE OR REPLACE FUNCTION public.create_emergency_case(_patient_id UUID,_chief_complaint TEXT,_acuity TEXT DEFAULT 'urgent',_arrival_mode TEXT DEFAULT 'walk_in',_assigned_officer UUID DEFAULT NULL)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE uid UUID := auth.uid(); v_id UUID; v_officer UUID;
BEGIN
 IF uid IS NULL OR NOT (public.has_role(uid,'admin') OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse') OR public.has_role(uid,'specialist_nurse') OR public.has_role(uid,'front_desk')) THEN RAISE EXCEPTION 'Emergency clinical role required'; END IF;
 IF _patient_id IS NULL OR NULLIF(trim(_chief_complaint),'') IS NULL THEN RAISE EXCEPTION 'Patient and chief complaint are required'; END IF;
 IF _acuity NOT IN ('resuscitation','emergency','urgent','less_urgent','non_urgent') THEN RAISE EXCEPTION 'Invalid acuity'; END IF;
 IF _arrival_mode NOT IN ('walk_in','ambulance','referral','other') THEN RAISE EXCEPTION 'Invalid arrival mode'; END IF;
 v_officer := COALESCE(_assigned_officer,CASE WHEN public.has_role(uid,'front_desk') THEN NULL ELSE uid END);
 INSERT INTO public.emergency_cases(patient_id,chief_complaint,acuity,arrival_mode,assigned_officer,status) VALUES (_patient_id,trim(_chief_complaint),_acuity,_arrival_mode,v_officer,CASE WHEN v_officer IS NULL THEN 'waiting' ELSE 'triage' END) RETURNING id INTO v_id;
 RETURN v_id;
END; $$;
CREATE OR REPLACE FUNCTION public.create_insurance_claim_draft(_patient_id UUID,_payer_name TEXT,_member_number TEXT DEFAULT NULL,_amount_claimed NUMERIC DEFAULT 0,_invoice_id UUID DEFAULT NULL)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE uid UUID := auth.uid(); v_id UUID;
BEGIN
 IF uid IS NULL OR NOT (public.has_role(uid,'admin') OR public.has_role(uid,'accountant') OR public.has_role(uid,'practitioner')) THEN RAISE EXCEPTION 'Claims role required'; END IF;
 IF _patient_id IS NULL OR NULLIF(trim(_payer_name),'') IS NULL THEN RAISE EXCEPTION 'Patient and payer are required'; END IF;
 IF _amount_claimed < 0 THEN RAISE EXCEPTION 'Claim amount cannot be negative'; END IF;
 INSERT INTO public.insurance_claims(patient_id,invoice_id,payer_name,member_number,amount_claimed,created_by,status) VALUES (_patient_id,_invoice_id,trim(_payer_name),NULLIF(trim(_member_number),''),_amount_claimed,uid,'draft') RETURNING id INTO v_id;
 RETURN v_id;
END; $$;
REVOKE ALL ON FUNCTION public.create_emergency_case(UUID,TEXT,TEXT,TEXT,UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_emergency_case(UUID,TEXT,TEXT,TEXT,UUID) TO authenticated;
REVOKE ALL ON FUNCTION public.create_insurance_claim_draft(UUID,TEXT,TEXT,NUMERIC,UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_insurance_claim_draft(UUID,TEXT,TEXT,NUMERIC,UUID) TO authenticated;
