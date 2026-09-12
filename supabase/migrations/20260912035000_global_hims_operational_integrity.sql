-- Global HIMS operational integrity: secure creation, assignment and financial edits.

CREATE OR REPLACE FUNCTION public.create_ward_unit(
  _name TEXT,
  _code TEXT,
  _specialty TEXT DEFAULT NULL,
  _gender_policy TEXT DEFAULT 'mixed'
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE uid UUID := auth.uid(); v_id UUID;
BEGIN
  IF uid IS NULL OR NOT public.has_role(uid,'admin') THEN RAISE EXCEPTION 'Administrator role required'; END IF;
  IF NULLIF(trim(_name),'') IS NULL OR NULLIF(trim(_code),'') IS NULL THEN RAISE EXCEPTION 'Ward name and code are required'; END IF;
  IF _gender_policy NOT IN ('mixed','male','female') THEN RAISE EXCEPTION 'Invalid gender policy'; END IF;
  INSERT INTO public.ward_units(name,code,specialty,gender_policy) VALUES (trim(_name),trim(_code),NULLIF(trim(_specialty),''),_gender_policy) RETURNING id INTO v_id;
  RETURN v_id;
END; $$;

CREATE OR REPLACE FUNCTION public.create_ward_bed(_ward_id UUID,_bed_number TEXT) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE uid UUID := auth.uid(); v_id UUID;
BEGIN
  IF uid IS NULL OR NOT (public.has_role(uid,'admin') OR public.has_role(uid,'nurse') OR public.has_role(uid,'specialist_nurse')) THEN RAISE EXCEPTION 'Nursing role required'; END IF;
  IF _ward_id IS NULL OR NULLIF(trim(_bed_number),'') IS NULL THEN RAISE EXCEPTION 'Ward and bed number are required'; END IF;
  INSERT INTO public.ward_beds(ward_id,bed_number,status) VALUES (_ward_id,trim(_bed_number),'available') RETURNING id INTO v_id;
  RETURN v_id;
END; $$;

CREATE OR REPLACE FUNCTION public.create_transfusion_record(
  _patient_id UUID,
  _blood_product TEXT,
  _unit_identifier TEXT,
  _blood_group TEXT DEFAULT NULL,
  _consent_confirmed BOOLEAN DEFAULT FALSE
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE uid UUID := auth.uid(); v_id UUID;
BEGIN
  IF uid IS NULL OR NOT (public.has_role(uid,'admin') OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse') OR public.has_role(uid,'specialist_nurse')) THEN RAISE EXCEPTION 'Clinical role required'; END IF;
  IF _patient_id IS NULL OR NULLIF(trim(_blood_product),'') IS NULL OR NULLIF(trim(_unit_identifier),'') IS NULL THEN RAISE EXCEPTION 'Patient, blood product and unit identifier are required'; END IF;
  INSERT INTO public.transfusion_records(patient_id,blood_product,unit_identifier,blood_group,consent_confirmed,status) VALUES (_patient_id,trim(_blood_product),trim(_unit_identifier),NULLIF(trim(_blood_group),''),COALESCE(_consent_confirmed,FALSE),'planned') RETURNING id INTO v_id;
  RETURN v_id;
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
DECLARE uid UUID := auth.uid(); v_id UUID;
BEGIN
  IF uid IS NULL OR NOT (public.has_role(uid,'admin') OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse') OR public.has_role(uid,'specialist_nurse')) THEN RAISE EXCEPTION 'Clinical role required'; END IF;
  IF _patient_id IS NULL OR NULLIF(trim(_procedure_name),'') IS NULL OR _scheduled_start IS NULL THEN RAISE EXCEPTION 'Patient, procedure and scheduled start are required'; END IF;
  IF _urgency NOT IN ('emergency','urgent','elective') THEN RAISE EXCEPTION 'Invalid urgency'; END IF;
  INSERT INTO public.theatre_cases(patient_id,procedure_name,scheduled_start,theatre_name,urgency,surgeon_id,created_by,status) VALUES (_patient_id,trim(_procedure_name),_scheduled_start,NULLIF(trim(_theatre_name),''),_urgency,COALESCE(_surgeon_id,uid),uid,'scheduled') RETURNING id INTO v_id;
  RETURN v_id;
END; $$;

CREATE OR REPLACE FUNCTION public.assign_theatre_anesthetist(_case_id UUID,_anesthetist_id UUID) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE uid UUID := auth.uid();
BEGIN
  IF uid IS NULL OR NOT (public.has_role(uid,'admin') OR public.has_role(uid,'practitioner')) THEN RAISE EXCEPTION 'Clinical administrator role required'; END IF;
  IF _anesthetist_id IS NULL THEN RAISE EXCEPTION 'Anesthetist is required'; END IF;
  UPDATE public.theatre_cases SET anesthetist_id=_anesthetist_id WHERE id=_case_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Theatre case not found'; END IF;
  RETURN jsonb_build_object('case_id',_case_id,'anesthetist_id',_anesthetist_id);
END; $$;

CREATE OR REPLACE FUNCTION public.update_insurance_claim_financials(
  _claim_id UUID,
  _amount_approved NUMERIC DEFAULT NULL,
  _amount_paid NUMERIC DEFAULT NULL,
  _claim_number TEXT DEFAULT NULL,
  _rejection_reason TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE uid UUID := auth.uid(); c public.insurance_claims%ROWTYPE; v_approved NUMERIC; v_paid NUMERIC;
BEGIN
  IF uid IS NULL OR NOT (public.has_role(uid,'admin') OR public.has_role(uid,'accountant')) THEN RAISE EXCEPTION 'Accounts role required'; END IF;
  SELECT * INTO c FROM public.insurance_claims WHERE id=_claim_id FOR UPDATE;
  IF c.id IS NULL THEN RAISE EXCEPTION 'Claim not found'; END IF;
  IF c.status IN ('paid','voided') THEN RAISE EXCEPTION 'Closed claim cannot be edited'; END IF;
  v_approved:=COALESCE(_amount_approved,c.amount_approved); v_paid:=COALESCE(_amount_paid,c.amount_paid);
  IF v_approved IS NOT NULL AND v_approved < 0 THEN RAISE EXCEPTION 'Approved amount cannot be negative'; END IF;
  IF v_paid < 0 OR (v_approved IS NOT NULL AND v_paid > v_approved) THEN RAISE EXCEPTION 'Invalid paid amount'; END IF;
  UPDATE public.insurance_claims SET amount_approved=COALESCE(_amount_approved,amount_approved),amount_paid=COALESCE(_amount_paid,amount_paid),claim_number=COALESCE(NULLIF(trim(_claim_number),''),claim_number),rejection_reason=COALESCE(_rejection_reason,rejection_reason) WHERE id=_claim_id;
  RETURN jsonb_build_object('claim_id',_claim_id,'amount_approved',v_approved,'amount_paid',v_paid);
END; $$;

REVOKE ALL ON FUNCTION public.create_ward_unit(TEXT,TEXT,TEXT,TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_ward_unit(TEXT,TEXT,TEXT,TEXT) TO authenticated;
REVOKE ALL ON FUNCTION public.create_ward_bed(UUID,TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_ward_bed(UUID,TEXT) TO authenticated;
REVOKE ALL ON FUNCTION public.create_transfusion_record(UUID,TEXT,TEXT,TEXT,BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_transfusion_record(UUID,TEXT,TEXT,TEXT,BOOLEAN) TO authenticated;
REVOKE ALL ON FUNCTION public.create_theatre_case(UUID,TEXT,TIMESTAMPTZ,TEXT,TEXT,UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_theatre_case(UUID,TEXT,TIMESTAMPTZ,TEXT,TEXT,UUID) TO authenticated;
REVOKE ALL ON FUNCTION public.assign_theatre_anesthetist(UUID,UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.assign_theatre_anesthetist(UUID,UUID) TO authenticated;
REVOKE ALL ON FUNCTION public.update_insurance_claim_financials(UUID,NUMERIC,NUMERIC,TEXT,TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.update_insurance_claim_financials(UUID,NUMERIC,NUMERIC,TEXT,TEXT) TO authenticated;
