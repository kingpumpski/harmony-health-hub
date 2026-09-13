-- Global HIMS reconciliation hardening: close remaining direct-write and
-- transition-integrity gaps without recreating legacy tables.

CREATE OR REPLACE FUNCTION public.create_nursing_shift_handover(
  _patient_id UUID,
  _shift_label TEXT,
  _clinical_summary TEXT,
  _pending_tasks TEXT DEFAULT NULL,
  _safety_concerns TEXT DEFAULT NULL,
  _escalation_required BOOLEAN DEFAULT FALSE,
  _ward_id UUID DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_id UUID;
BEGIN
  IF auth.uid() IS NULL OR NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife') OR public.has_role(auth.uid(),'specialist_nurse')) THEN
    RAISE EXCEPTION 'Nursing role required';
  END IF;
  IF NULLIF(trim(_clinical_summary),'') IS NULL THEN RAISE EXCEPTION 'Clinical summary is required'; END IF;
  INSERT INTO public.nursing_shift_handovers(patient_id,ward_id,outgoing_officer,shift_label,clinical_summary,pending_tasks,safety_concerns,escalation_required)
  VALUES (_patient_id,_ward_id,auth.uid(),COALESCE(NULLIF(trim(_shift_label),''),'unspecified'),_clinical_summary,_pending_tasks,_safety_concerns,COALESCE(_escalation_required,FALSE))
  RETURNING id INTO v_id;
  RETURN v_id;
END; $$;

CREATE OR REPLACE FUNCTION public.assign_emergency_officer(
  _case_id UUID,
  _officer_id UUID DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE uid UUID := auth.uid(); v_officer UUID;
BEGIN
  IF uid IS NULL OR NOT (public.has_role(uid,'admin') OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse') OR public.has_role(uid,'specialist_nurse')) THEN
    RAISE EXCEPTION 'Clinical role required';
  END IF;
  v_officer := COALESCE(_officer_id,uid);
  UPDATE public.emergency_cases SET assigned_officer=v_officer WHERE id=_case_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Emergency case not found'; END IF;
  RETURN jsonb_build_object('case_id',_case_id,'assigned_officer',v_officer);
END; $$;

CREATE OR REPLACE FUNCTION public.update_insurance_claim_financials(
  _claim_id UUID,
  _amount_approved NUMERIC DEFAULT NULL,
  _amount_paid NUMERIC DEFAULT NULL,
  _claim_number TEXT DEFAULT NULL,
  _rejection_reason TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE uid UUID := auth.uid(); c public.insurance_claims%ROWTYPE;
BEGIN
  IF uid IS NULL OR NOT (public.has_role(uid,'admin') OR public.has_role(uid,'accountant')) THEN RAISE EXCEPTION 'Accounts role required'; END IF;
  SELECT * INTO c FROM public.insurance_claims WHERE id=_claim_id FOR UPDATE;
  IF c.id IS NULL THEN RAISE EXCEPTION 'Claim not found'; END IF;
  IF c.status IN ('paid','voided') THEN RAISE EXCEPTION 'Closed claim cannot be edited'; END IF;
  IF _amount_approved IS NOT NULL AND _amount_approved < 0 THEN RAISE EXCEPTION 'Approved amount cannot be negative'; END IF;
  IF _amount_paid IS NOT NULL AND _amount_paid < 0 THEN RAISE EXCEPTION 'Paid amount cannot be negative'; END IF;
  IF _amount_paid IS NOT NULL AND _amount_approved IS NOT NULL AND _amount_paid > _amount_approved THEN RAISE EXCEPTION 'Paid amount cannot exceed approved amount'; END IF;
  UPDATE public.insurance_claims
  SET amount_approved=COALESCE(_amount_approved,amount_approved),
      amount_paid=COALESCE(_amount_paid,amount_paid),
      claim_number=COALESCE(NULLIF(trim(_claim_number),''),claim_number),
      rejection_reason=COALESCE(_rejection_reason,rejection_reason)
  WHERE id=_claim_id;
  RETURN jsonb_build_object('claim_id',_claim_id);
END; $$;

CREATE OR REPLACE FUNCTION public.record_transfusion_reaction(
  _record_id UUID,
  _reaction_observed BOOLEAN,
  _reaction_notes TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE uid UUID := auth.uid(); r public.transfusion_records%ROWTYPE;
BEGIN
  IF uid IS NULL OR NOT (public.has_role(uid,'admin') OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse') OR public.has_role(uid,'specialist_nurse')) THEN RAISE EXCEPTION 'Clinical role required'; END IF;
  SELECT * INTO r FROM public.transfusion_records WHERE id=_record_id FOR UPDATE;
  IF r.id IS NULL THEN RAISE EXCEPTION 'Transfusion record not found'; END IF;
  UPDATE public.transfusion_records SET reaction_observed=COALESCE(_reaction_observed,FALSE), reaction_notes=COALESCE(_reaction_notes,reaction_notes), witnessed_by=COALESCE(witnessed_by,uid) WHERE id=_record_id;
  RETURN jsonb_build_object('record_id',_record_id,'reaction_observed',COALESCE(_reaction_observed,FALSE));
END; $$;

REVOKE ALL ON FUNCTION public.create_nursing_shift_handover(UUID,TEXT,TEXT,TEXT,TEXT,BOOLEAN,UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_nursing_shift_handover(UUID,TEXT,TEXT,TEXT,TEXT,BOOLEAN,UUID) TO authenticated;
REVOKE ALL ON FUNCTION public.assign_emergency_officer(UUID,UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.assign_emergency_officer(UUID,UUID) TO authenticated;
REVOKE ALL ON FUNCTION public.update_insurance_claim_financials(UUID,NUMERIC,NUMERIC,TEXT,TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.update_insurance_claim_financials(UUID,NUMERIC,NUMERIC,TEXT,TEXT) TO authenticated;
REVOKE ALL ON FUNCTION public.record_transfusion_reaction(UUID,BOOLEAN,TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.record_transfusion_reaction(UUID,BOOLEAN,TEXT) TO authenticated;
