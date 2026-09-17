-- Secure scheduling transition for the specialist referral queue.
CREATE OR REPLACE FUNCTION public.schedule_patient_referral_workflow(_referral_id UUID)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_status TEXT; v_patient UUID; v_specialty TEXT;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife') OR public.has_role(auth.uid(),'specialist_nurse') OR public.has_role(auth.uid(),'front_desk')) THEN RAISE EXCEPTION 'Referral scheduling is not permitted'; END IF;
  SELECT status,patient_id,specialty INTO v_status,v_patient,v_specialty FROM public.patient_referrals WHERE id=_referral_id FOR UPDATE;
  IF v_status IS NULL THEN RAISE EXCEPTION 'Referral not found'; END IF;
  IF v_status NOT IN ('requested','accepted') THEN RAISE EXCEPTION 'Referral is not awaiting scheduling'; END IF;
  UPDATE public.patient_referrals SET status='scheduled',updated_at=now() WHERE id=_referral_id;
  PERFORM public.record_system_audit('referral_scheduled','care_transitions','patient_referral',_referral_id,'info',jsonb_build_object('patient_id',v_patient,'specialty',v_specialty));
  RETURN jsonb_build_object('referral_id',_referral_id,'status','scheduled');
END; $$;
REVOKE ALL ON FUNCTION public.schedule_patient_referral_workflow(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.schedule_patient_referral_workflow(UUID) TO authenticated;
