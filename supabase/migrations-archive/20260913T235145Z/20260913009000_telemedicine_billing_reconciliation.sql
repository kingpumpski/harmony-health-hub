-- Telemedicine billing reconciliation.
-- A scheduled video consultation owns a billable service order; the session cannot start
-- until the billing workflow releases that order. Manual payment flags are no longer trusted.

ALTER TABLE public.video_sessions
  ADD COLUMN IF NOT EXISTS service_order_id UUID REFERENCES public.service_orders(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_video_sessions_service_order ON public.video_sessions(service_order_id);

CREATE OR REPLACE FUNCTION public.schedule_video_session(
  _patient_id UUID,
  _scheduled_at TIMESTAMPTZ,
  _provider TEXT DEFAULT 'jitsi'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id UUID;
  v_room TEXT;
  v_tariff RECORD;
  v_order_id UUID;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner')) THEN
    RAISE EXCEPTION 'Telemedicine scheduling requires a practitioner role';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.patients WHERE id = _patient_id) THEN
    RAISE EXCEPTION 'Patient not found';
  END IF;
  IF _scheduled_at IS NULL OR _scheduled_at < now() - interval '5 minutes' THEN
    RAISE EXCEPTION 'A valid future appointment time is required';
  END IF;

  SELECT id, service_code, service_name, department, amount
    INTO v_tariff
  FROM public.service_tariffs
  WHERE active = true
    AND upper(service_code) = 'TELEMEDICINE'
  LIMIT 1;

  IF v_tariff.id IS NULL THEN
    RAISE EXCEPTION 'Configure an active TELEMEDICINE service tariff before scheduling';
  END IF;
  IF COALESCE(v_tariff.amount,0) <= 0 THEN
    RAISE EXCEPTION 'The TELEMEDICINE service tariff must have a charge greater than zero';
  END IF;

  v_room := 'harmony-' || replace(gen_random_uuid()::text, '-', '');

  INSERT INTO public.video_sessions (
    patient_id, practitioner_id, room_name, provider, scheduled_at, status,
    payment_required, payment_received
  ) VALUES (
    _patient_id, auth.uid(), v_room, COALESCE(NULLIF(trim(_provider), ''), 'jitsi'), _scheduled_at,
    'scheduled', true, false
  ) RETURNING id INTO v_id;

  INSERT INTO public.service_orders (
    patient_id, department, service_name, related_entity_id, amount, status,
    notes, requested_by, order_type, service_code, quantity, unit_price,
    payment_required, created_by
  ) VALUES (
    _patient_id,
    v_tariff.department,
    v_tariff.service_name,
    v_id,
    v_tariff.amount,
    'pending_payment_approval',
    'Telemedicine consultation scheduled for ' || _scheduled_at::text,
    auth.uid(),
    'telemedicine',
    v_tariff.service_code,
    1,
    v_tariff.amount,
    true,
    auth.uid()
  ) RETURNING id INTO v_order_id;

  UPDATE public.video_sessions
  SET service_order_id = v_order_id
  WHERE id = v_id;

  PERFORM public.record_system_audit(
    'telemedicine_session_scheduled',
    'telemedicine',
    'video_session',
    v_id,
    'info',
    jsonb_build_object('patient_id',_patient_id,'service_order_id',v_order_id,'scheduled_at',_scheduled_at)
  );

  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.mark_video_session_paid(_session_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_order_status TEXT;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'accountant') OR public.has_role(auth.uid(),'front_desk')) THEN
    RAISE EXCEPTION 'Payment confirmation requires an accounts or front-desk role';
  END IF;

  SELECT so.status INTO v_order_status
  FROM public.video_sessions vs
  JOIN public.service_orders so ON so.id = vs.service_order_id
  WHERE vs.id = _session_id;

  IF v_order_status IS NULL THEN RAISE EXCEPTION 'Telemedicine billing order not found'; END IF;
  IF v_order_status <> 'released' THEN
    RAISE EXCEPTION 'Telemedicine payment must be completed through Billing before the session is released';
  END IF;

  UPDATE public.video_sessions
  SET payment_received = true
  WHERE id = _session_id AND status IN ('scheduled','ready');

  RETURN FOUND;
END;
$$;

CREATE OR REPLACE FUNCTION public.start_video_session(_session_id UUID)
RETURNS TABLE(id UUID, room_name TEXT, provider TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner')) THEN
    RAISE EXCEPTION 'Telemedicine access requires a practitioner role';
  END IF;

  UPDATE public.video_sessions vs
  SET status = 'active', started_at = COALESCE(vs.started_at, now())
  WHERE vs.id = _session_id
    AND vs.practitioner_id = auth.uid()
    AND vs.status IN ('scheduled','ready')
    AND vs.service_order_id IS NOT NULL
    AND EXISTS (
      SELECT 1 FROM public.service_orders so
      WHERE so.id = vs.service_order_id AND so.status = 'released'
    );

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Session is unavailable, not assigned to you, or the telemedicine bill is outstanding';
  END IF;

  UPDATE public.service_orders
  SET status = 'in_progress', started_at = COALESCE(started_at, now())
  WHERE id = (SELECT service_order_id FROM public.video_sessions WHERE id = _session_id)
    AND status = 'released';

  RETURN QUERY SELECT v.id, v.room_name, v.provider FROM public.video_sessions v WHERE v.id = _session_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.end_video_session(_session_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_order_id UUID;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner')) THEN
    RAISE EXCEPTION 'Telemedicine access requires a practitioner role';
  END IF;

  SELECT service_order_id INTO v_order_id
  FROM public.video_sessions
  WHERE id = _session_id AND practitioner_id = auth.uid() AND status = 'active';

  IF v_order_id IS NULL THEN RETURN false; END IF;

  UPDATE public.video_sessions
  SET status = 'completed', ended_at = COALESCE(ended_at, now())
  WHERE id = _session_id AND status = 'active';

  UPDATE public.service_orders
  SET status = 'completed', completed_at = COALESCE(completed_at, now())
  WHERE id = v_order_id AND status = 'in_progress';

  PERFORM public.record_system_audit(
    'telemedicine_session_completed',
    'telemedicine',
    'video_session',
    _session_id,
    'info',
    jsonb_build_object('service_order_id',v_order_id)
  );
  RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION public.schedule_video_session(UUID,TIMESTAMPTZ,TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.mark_video_session_paid(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.start_video_session(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.end_video_session(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.schedule_video_session(UUID,TIMESTAMPTZ,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_video_session_paid(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.start_video_session(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.end_video_session(UUID) TO authenticated;
