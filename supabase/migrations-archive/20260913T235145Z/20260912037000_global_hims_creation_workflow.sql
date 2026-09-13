-- Global HIMS creation workflow hardening.
-- Adds server-authoritative creation for emergency cases and insurance claims.
-- Reconciles the UI with the existing global HIMS tables without creating duplicates.

CREATE OR REPLACE FUNCTION public.create_emergency_case(
  _patient_id UUID,
  _chief_complaint TEXT,
  _acuity TEXT DEFAULT 'urgent',
  _arrival_mode TEXT DEFAULT 'walk_in',
  _assigned_officer UUID DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  uid UUID := auth.uid();
  v_id UUID;
  v_assigned UUID;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (public.has_role(uid,'admin') OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse') OR public.has_role(uid,'specialist_nurse') OR public.has_role(uid,'front_desk')) THEN
    RAISE EXCEPTION 'Emergency operations role required';
  END IF;
  IF _patient_id IS NULL OR NULLIF(trim(_chief_complaint),'') IS NULL THEN
    RAISE EXCEPTION 'Patient and chief complaint are required';
  END IF;
  IF _acuity NOT IN ('resuscitation','emergency','urgent','less_urgent','non_urgent') THEN
    RAISE EXCEPTION 'Invalid emergency acuity';
  END IF;
  IF _arrival_mode NOT IN ('walk_in','ambulance','referral','other') THEN
    RAISE EXCEPTION 'Invalid arrival mode';
  END IF;
  IF _assigned_officer IS NOT NULL AND _assigned_officer <> uid AND NOT public.has_role(uid,'admin') THEN
    RAISE EXCEPTION 'Only an administrator may assign another officer during creation';
  END IF;
  v_assigned := COALESCE(_assigned_officer, uid);
  INSERT INTO public.emergency_cases(patient_id,arrival_mode,acuity,chief_complaint,assigned_officer,status)
  VALUES (_patient_id,_arrival_mode,_acuity,trim(_chief_complaint),v_assigned,'waiting')
  RETURNING id INTO v_id;
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
DECLARE
  uid UUID := auth.uid();
  v_id UUID;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (public.has_role(uid,'admin') OR public.has_role(uid,'accountant') OR public.has_role(uid,'practitioner') OR public.has_role(uid,'front_desk')) THEN
    RAISE EXCEPTION 'Claims operations role required';
  END IF;
  IF _patient_id IS NULL OR NULLIF(trim(_payer_name),'') IS NULL THEN
    RAISE EXCEPTION 'Patient and payer are required';
  END IF;
  IF COALESCE(_amount_claimed,0) < 0 THEN RAISE EXCEPTION 'Claim amount cannot be negative'; END IF;
  INSERT INTO public.insurance_claims(patient_id,invoice_id,payer_name,member_number,amount_claimed,status,created_by)
  VALUES (_patient_id,_invoice_id,trim(_payer_name),NULLIF(trim(_member_number),''),COALESCE(_amount_claimed,0),'draft',uid)
  RETURNING id INTO v_id;
  INSERT INTO public.insurance_claim_events(claim_id,event_type,to_status,notes,actor_id)
  VALUES (v_id,'created','draft','Claim draft created',uid);
  RETURN v_id;
END; $$;

REVOKE ALL ON FUNCTION public.create_emergency_case(UUID,TEXT,TEXT,TEXT,UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_emergency_case(UUID,TEXT,TEXT,TEXT,UUID) TO authenticated;
REVOKE ALL ON FUNCTION public.create_insurance_claim_draft(UUID,TEXT,TEXT,NUMERIC,UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_insurance_claim_draft(UUID,TEXT,TEXT,NUMERIC,UUID) TO authenticated;
