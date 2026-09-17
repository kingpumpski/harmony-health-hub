-- Bridge scheduled specialist referrals into the appointment workflow.
-- A scheduled referral with an appointment date creates exactly one specialist appointment
-- in the same transaction as the referral status transition.
CREATE OR REPLACE FUNCTION public.schedule_patient_referral_workflow(_referral_id UUID)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  v_status TEXT;
  v_patient UUID;
  v_specialty TEXT;
  v_reason TEXT;
  v_destination TEXT;
  v_appointment_date TIMESTAMPTZ;
  v_appointment_id UUID;
  v_existing UUID;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (
    public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner')
    OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife')
    OR public.has_role(auth.uid(),'specialist_nurse') OR public.has_role(auth.uid(),'front_desk')
  ) THEN RAISE EXCEPTION 'Referral scheduling is not permitted'; END IF;

  SELECT status,patient_id,specialty,reason,destination,appointment_date
    INTO v_status,v_patient,v_specialty,v_reason,v_destination,v_appointment_date
  FROM public.patient_referrals
  WHERE id=_referral_id
  FOR UPDATE;

  IF v_status IS NULL THEN RAISE EXCEPTION 'Referral not found'; END IF;
  IF v_status NOT IN ('requested','accepted') THEN RAISE EXCEPTION 'Referral is not awaiting scheduling'; END IF;
  IF v_appointment_date IS NULL THEN RAISE EXCEPTION 'A specialist appointment date is required before initiation'; END IF;
  IF v_appointment_date < now() THEN RAISE EXCEPTION 'The specialist appointment date must be in the future'; END IF;

  SELECT a.id INTO v_existing
  FROM public.appointments a
  WHERE a.patient_id=v_patient
    AND a.scheduled_at=v_appointment_date
    AND COALESCE(a.department,'')=COALESCE(v_specialty,v_destination,'specialist')
    AND COALESCE(a.reason,'')=COALESCE(v_reason,'')
    AND a.status NOT IN ('cancelled','no_show')
  ORDER BY a.created_at DESC
  LIMIT 1;

  IF v_existing IS NULL THEN
    SELECT id INTO v_appointment_id
    FROM public.create_appointment_workflow(
      v_patient,
      v_appointment_date,
      COALESCE(NULLIF(trim(v_specialty),''),NULLIF(trim(v_destination),''),'specialist'),
      v_reason
    );
  ELSE
    v_appointment_id := v_existing;
  END IF;

  UPDATE public.patient_referrals
  SET status='scheduled',updated_at=now()
  WHERE id=_referral_id;

  PERFORM public.record_system_audit(
    'referral_scheduled','care_transitions','patient_referral',_referral_id,'info',
    jsonb_build_object('patient_id',v_patient,'specialty',v_specialty,'appointment_id',v_appointment_id,'appointment_date',v_appointment_date)
  );

  RETURN jsonb_build_object(
    'referral_id',_referral_id,
    'status','scheduled',
    'appointment_id',v_appointment_id,
    'appointment_date',v_appointment_date
  );
END; $$;

REVOKE ALL ON FUNCTION public.schedule_patient_referral_workflow(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.schedule_patient_referral_workflow(UUID) TO authenticated;
