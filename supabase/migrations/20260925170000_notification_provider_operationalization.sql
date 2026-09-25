-- Notification provider operationalization: FCM device registry, provider health, webhook idempotency,
-- consent capture helpers, and test-tier provider configuration. Credentials remain secrets/env vars.

CREATE TABLE IF NOT EXISTS public.notification_devices (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  provider TEXT NOT NULL CHECK (provider IN ('fcm')),
  platform TEXT NOT NULL CHECK (platform IN ('web','android','ios')),
  token TEXT NOT NULL,
  device_label TEXT,
  active BOOLEAN NOT NULL DEFAULT true,
  last_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(provider, token)
);
CREATE INDEX IF NOT EXISTS idx_notification_devices_user_active
  ON public.notification_devices(user_id, provider, active);

CREATE TABLE IF NOT EXISTS public.notification_provider_health (
  provider TEXT PRIMARY KEY,
  channel TEXT NOT NULL CHECK (channel IN ('email','push','sms','whatsapp','voice')),
  consecutive_failures INTEGER NOT NULL DEFAULT 0,
  circuit_state TEXT NOT NULL DEFAULT 'closed' CHECK (circuit_state IN ('closed','open','half_open')),
  opened_at TIMESTAMPTZ,
  next_probe_at TIMESTAMPTZ,
  last_error TEXT,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.notification_webhook_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  provider TEXT NOT NULL,
  external_event_id TEXT NOT NULL,
  event_type TEXT NOT NULL,
  payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  received_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  processed_at TIMESTAMPTZ,
  UNIQUE(provider, external_event_id)
);

ALTER TABLE public.notification_channels
  ADD COLUMN IF NOT EXISTS environment TEXT NOT NULL DEFAULT 'sandbox'
    CHECK (environment IN ('sandbox','test','production')),
  ADD COLUMN IF NOT EXISTS webhook_enabled BOOLEAN NOT NULL DEFAULT false;

INSERT INTO public.notification_provider_health(provider,channel)
VALUES ('resend','email'),('fcm','push'),('twilio','sms'),('twilio-whatsapp','whatsapp'),('twilio-voice','voice')
ON CONFLICT(provider) DO NOTHING;

UPDATE public.notification_channels
SET provider='resend', environment='sandbox'
WHERE code='email' AND provider IS NULL;

UPDATE public.notification_channels
SET provider='fcm', environment='sandbox'
WHERE code='push' AND provider IS NULL;

UPDATE public.notification_channels
SET provider='twilio', environment='sandbox'
WHERE code='sms' AND provider IS NULL;

UPDATE public.notification_channels
SET provider='twilio', environment='sandbox'
WHERE code='whatsapp' AND provider IS NULL;

UPDATE public.notification_channels
SET provider='twilio', environment='sandbox'
WHERE code='voice' AND provider IS NULL;

CREATE OR REPLACE FUNCTION public.register_notification_device(
  _provider TEXT, _platform TEXT, _token TEXT, _device_label TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public
AS $$
DECLARE result_id UUID;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF _provider <> 'fcm' THEN RAISE EXCEPTION 'Unsupported push provider'; END IF;
  IF length(trim(_token)) < 20 THEN RAISE EXCEPTION 'Invalid device token'; END IF;

  INSERT INTO public.notification_devices(user_id,provider,platform,token,device_label,active,last_seen_at,updated_at)
  VALUES(auth.uid(),_provider,_platform,trim(_token),_device_label,true,now(),now())
  ON CONFLICT(provider,token)
  DO UPDATE SET user_id=auth.uid(), platform=excluded.platform, device_label=excluded.device_label,
                active=true, last_seen_at=now(), updated_at=now()
  RETURNING id INTO result_id;
  RETURN result_id;
END;
$$;

REVOKE ALL ON FUNCTION public.register_notification_device(TEXT,TEXT,TEXT,TEXT) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.register_notification_device(TEXT,TEXT,TEXT,TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.revoke_notification_device(_token TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  UPDATE public.notification_devices SET active=false, updated_at=now()
  WHERE user_id=auth.uid() AND token=_token;
  RETURN FOUND;
END;
$$;

REVOKE ALL ON FUNCTION public.revoke_notification_device(TEXT) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.revoke_notification_device(TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.record_notification_consent(
  _channel TEXT, _category TEXT, _granted BOOLEAN, _consent_version TEXT, _user_agent TEXT DEFAULT NULL, _consent_ip INET DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public
AS $$
DECLARE result_id UUID;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;

  INSERT INTO public.notification_consent_audit(user_id,channel,category,granted,consent_version,consented_at,consent_ip,user_agent)
  VALUES(auth.uid(),_channel,_category,_granted,_consent_version,now(),_consent_ip,_user_agent)
  RETURNING id INTO result_id;

  UPDATE public.user_notification_preferences
  SET consent_version=_consent_version, consented_at=now(), updated_at=now()
  WHERE user_id=auth.uid();

  RETURN result_id;
END;
$$;

REVOKE ALL ON FUNCTION public.record_notification_consent(TEXT,TEXT,BOOLEAN,TEXT,TEXT,INET) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.record_notification_consent(TEXT,TEXT,BOOLEAN,TEXT,TEXT,INET) TO authenticated;

CREATE OR REPLACE FUNCTION public.prevent_notification_audit_mutation()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $1
  IF TG_OP = 'DELETE' AND current_setting('notification.audit_erasure', true) = 'on' THEN
    RETURN OLD;
  END IF;
  RAISE EXCEPTION 'Notification audit is immutable';
END;
$;

DROP TRIGGER IF EXISTS notification_audit_immutable ON public.notification_audit;
CREATE TRIGGER notification_audit_immutable
BEFORE UPDATE OR DELETE ON public.notification_audit
FOR EACH ROW EXECUTE FUNCTION public.prevent_notification_audit_mutation();

CREATE OR REPLACE FUNCTION public.erase_notification_history(_user_id UUID DEFAULT auth.uid())
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public
AS $
DECLARE deleted_count INTEGER := 0;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF _user_id <> auth.uid() AND NOT public.has_role(auth.uid(),'admin') THEN
    RAISE EXCEPTION 'Forbidden'; END IF;

  -- Authorized erasure is the only controlled exception to immutable audit retention.
  PERFORM set_config('notification.audit_erasure','on',true);

  DELETE FROM public.notifications WHERE recipient_user_id=_user_id;
  DELETE FROM public.notification_queue WHERE user_id=_user_id;
  DELETE FROM public.notification_delivery_logs WHERE user_id=_user_id;
  GET DIAGNOSTICS deleted_count = ROW_COUNT;
  DELETE FROM public.notification_audit WHERE user_id=_user_id;
  DELETE FROM public.notification_consent_audit WHERE user_id=_user_id;
  DELETE FROM public.notification_devices WHERE user_id=_user_id;
  DELETE FROM public.scheduled_notifications WHERE user_id=_user_id;
  DELETE FROM public.user_notification_preferences WHERE user_id=_user_id;
  RETURN deleted_count;
END;
$;

REVOKE ALL ON FUNCTION public.erase_notification_history(UUID) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.erase_notification_history(UUID) TO authenticated;

ALTER TABLE public.notification_devices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notification_provider_health ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notification_webhook_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY "notification devices own read" ON public.notification_devices
  FOR SELECT TO authenticated USING(user_id=auth.uid() OR public.has_role(auth.uid(),'admin'));
CREATE POLICY "notification devices own delete" ON public.notification_devices
  FOR DELETE TO authenticated USING(user_id=auth.uid() OR public.has_role(auth.uid(),'admin'));
CREATE POLICY "notification provider health admin read" ON public.notification_provider_health
  FOR SELECT TO authenticated USING(public.has_role(auth.uid(),'admin'));
CREATE POLICY "notification webhook events admin read" ON public.notification_webhook_events
  FOR SELECT TO authenticated USING(public.has_role(auth.uid(),'admin'));

-- Provider enablement remains OFF until sandbox credentials and consent tests are completed.
UPDATE public.notification_channels
SET enabled=false, webhook_enabled=false
WHERE code IN ('email','push','sms','whatsapp','voice');
