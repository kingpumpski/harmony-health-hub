-- Notification queue authorization reconciliation.
-- Service-role workers may enqueue scheduled system notifications; user-facing callers remain scoped to self/admin.
CREATE OR REPLACE FUNCTION public.enqueue_notification_v2(
  _event_name TEXT, _user_id UUID, _payload JSONB, _template_key TEXT,
  _channels JSONB DEFAULT '["in_app"]'::jsonb, _priority TEXT DEFAULT 'medium',
  _scheduled_for TIMESTAMPTZ DEFAULT now(), _idempotency_key TEXT DEFAULT NULL,
  _tenant_id UUID DEFAULT NULL, _locale TEXT DEFAULT NULL, _timezone TEXT DEFAULT NULL, _facility_id UUID DEFAULT NULL
)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  qid UUID;
  idem TEXT := COALESCE(_idempotency_key, _event_name || ':' || _user_id::text || ':' || md5(COALESCE(_payload,'{}'::jsonb)::text));
  v_service_role BOOLEAN := current_setting('request.jwt.claim.role', true) = 'service_role';
BEGIN
  IF _user_id IS NULL THEN RAISE EXCEPTION 'Notification recipient required'; END IF;
  IF NOT v_service_role AND (
    auth.uid() IS NULL OR
    (_user_id <> auth.uid() AND NOT public.has_role(auth.uid(),'admin'))
  ) THEN RAISE EXCEPTION 'Forbidden'; END IF;
  IF _facility_id IS NOT NULL AND NOT v_service_role AND NOT public.has_facility_access(auth.uid(),_facility_id) THEN
    RAISE EXCEPTION 'Facility access required';
  END IF;
  IF NOT EXISTS(SELECT 1 FROM public.notification_events WHERE event_name=_event_name AND enabled) THEN
    RAISE EXCEPTION 'Notification event is disabled or unknown';
  END IF;
  INSERT INTO public.notification_queue(
    channel,payload,status,idempotency_key,tenant_id,user_id,priority,event_name,template_key,locale,timezone,
    scheduled_for,fallback_channels,next_attempt_at,facility_id
  )
  VALUES(
    COALESCE(_channels->>0,'in_app'),COALESCE(_payload,'{}'::jsonb),'pending',idem,_tenant_id,_user_id,_priority,
    _event_name,_template_key,_locale,_timezone,COALESCE(_scheduled_for,now()),COALESCE(_channels,'["in_app"]'::jsonb),
    COALESCE(_scheduled_for,now()),_facility_id
  )
  ON CONFLICT(idempotency_key) DO UPDATE SET updated_at=now()
  RETURNING id INTO qid;
  IF qid IS NULL THEN SELECT id INTO qid FROM public.notification_queue WHERE idempotency_key=idem; END IF;
  RETURN qid;
END; $$;

REVOKE ALL ON FUNCTION public.enqueue_notification_v2(TEXT,UUID,JSONB,TEXT,JSONB,TEXT,TIMESTAMPTZ,TEXT,UUID,TEXT,TEXT,UUID) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.enqueue_notification_v2(TEXT,UUID,JSONB,TEXT,JSONB,TEXT,TIMESTAMPTZ,TEXT,UUID,TEXT,TEXT,UUID) TO authenticated,service_role;
