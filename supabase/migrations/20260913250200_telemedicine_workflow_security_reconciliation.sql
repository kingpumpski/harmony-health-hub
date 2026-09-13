-- Telemedicine workflow reconciliation for the active Harmony database.
-- Canonical role model excludes the retired specialist_nurse role.

CREATE OR REPLACE FUNCTION public.schedule_video_session(_patient_id UUID,_scheduled_at TIMESTAMPTZ,_provider TEXT DEFAULT 'jitsi')
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_id UUID; v_room TEXT;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner')) THEN RAISE EXCEPTION 'Telemedicine scheduling requires a practitioner role'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.patients WHERE id=_patient_id) THEN RAISE EXCEPTION 'Patient not found'; END IF;
  IF _scheduled_at IS NULL OR _scheduled_at < now()-interval '5 minutes' THEN RAISE EXCEPTION 'A valid future appointment time is required'; END IF;
  v_room := 'harmony-' || replace(gen_random_uuid()::text,'-','');
  INSERT INTO public.video_sessions(patient_id,practitioner_id,room_name,provider,scheduled_at,status,payment_required,payment_received)
  VALUES(_patient_id,auth.uid(),v_room,COALESCE(NULLIF(trim(_provider),''),'jitsi'),_scheduled_at,'scheduled',true,false) RETURNING id INTO v_id;
  RETURN v_id;
END; $$;

CREATE OR REPLACE FUNCTION public.mark_video_session_paid(_session_id UUID)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'accountant') OR public.has_role(auth.uid(),'front_desk')) THEN RAISE EXCEPTION 'Payment confirmation requires an accounts or front-desk role'; END IF;
  UPDATE public.video_sessions SET payment_received=true WHERE id=_session_id AND status IN ('scheduled','ready');
  RETURN FOUND;
END; $$;

CREATE OR REPLACE FUNCTION public.start_video_session(_session_id UUID)
RETURNS TABLE(id UUID,room_name TEXT,provider TEXT) LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner')) THEN RAISE EXCEPTION 'Telemedicine access requires a practitioner role'; END IF;
  UPDATE public.video_sessions SET status='active',started_at=COALESCE(started_at,now()) WHERE video_sessions.id=_session_id AND practitioner_id=auth.uid() AND status IN ('scheduled','ready') AND (NOT payment_required OR payment_received);
  IF NOT FOUND THEN RAISE EXCEPTION 'Session is unavailable, not assigned to you, or payment is outstanding'; END IF;
  RETURN QUERY SELECT v.id,v.room_name,v.provider FROM public.video_sessions v WHERE v.id=_session_id;
END; $$;

CREATE OR REPLACE FUNCTION public.end_video_session(_session_id UUID)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner')) THEN RAISE EXCEPTION 'Telemedicine access requires a practitioner role'; END IF;
  UPDATE public.video_sessions SET status='completed',ended_at=COALESCE(ended_at,now()) WHERE id=_session_id AND practitioner_id=auth.uid() AND status='active';
  RETURN FOUND;
END; $$;

REVOKE ALL ON FUNCTION public.schedule_video_session(UUID,TIMESTAMPTZ,TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.mark_video_session_paid(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.start_video_session(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.end_video_session(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.schedule_video_session(UUID,TIMESTAMPTZ,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_video_session_paid(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.start_video_session(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.end_video_session(UUID) TO authenticated;
REVOKE INSERT,UPDATE,DELETE ON public.video_sessions FROM authenticated;
GRANT SELECT ON public.video_sessions TO authenticated;
NOTIFY pgrst,'reload schema';
