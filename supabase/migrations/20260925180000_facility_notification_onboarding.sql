-- Organization/facility onboarding configuration for production notification providers.
-- Provider credentials are NEVER stored here. This table stores operational configuration
-- and secret references only; credentials belong in the deployment/provider secret store.

CREATE TABLE IF NOT EXISTS public.facility_notification_config (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  facility_id UUID NOT NULL UNIQUE REFERENCES public.healthcare_facilities(id) ON DELETE CASCADE,
  environment TEXT NOT NULL DEFAULT 'sandbox' CHECK (environment IN ('sandbox','test','production')),
  enabled BOOLEAN NOT NULL DEFAULT false,
  default_locale TEXT NOT NULL DEFAULT 'en-GH',
  default_timezone TEXT NOT NULL DEFAULT 'Africa/Accra',
  quiet_hours_start TIME NOT NULL DEFAULT '22:00',
  quiet_hours_end TIME NOT NULL DEFAULT '07:00',
  enabled_channels JSONB NOT NULL DEFAULT '{"in_app":true,"email":false,"sms":false,"push":false,"whatsapp":false,"voice":false}'::jsonb,
  provider_config JSONB NOT NULL DEFAULT '{}'::jsonb,
  sender_config JSONB NOT NULL DEFAULT '{}'::jsonb,
  webhook_config JSONB NOT NULL DEFAULT '{}'::jsonb,
  consent_policy JSONB NOT NULL DEFAULT '{"external_channels_require_consent":true,"critical_override_enabled":true}'::jsonb,
  rollout_percent INTEGER NOT NULL DEFAULT 0 CHECK (rollout_percent BETWEEN 0 AND 100),
  kill_switch BOOLEAN NOT NULL DEFAULT false,
  onboarding_status TEXT NOT NULL DEFAULT 'not_started'
    CHECK (onboarding_status IN ('not_started','in_progress','sandbox_ready','verification_pending','production_ready','suspended')),
  verified_at TIMESTAMPTZ,
  verified_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  updated_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.facility_notification_provider_connections (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  facility_id UUID NOT NULL REFERENCES public.healthcare_facilities(id) ON DELETE CASCADE,
  channel TEXT NOT NULL CHECK (channel IN ('email','sms','push','whatsapp','voice')),
  provider TEXT NOT NULL,
  environment TEXT NOT NULL DEFAULT 'sandbox' CHECK (environment IN ('sandbox','test','production')),
  secret_reference TEXT,
  sender_identity TEXT,
  account_reference TEXT,
  status TEXT NOT NULL DEFAULT 'not_configured'
    CHECK (status IN ('not_configured','configured','verification_pending','verified','failed','disabled')),
  last_verified_at TIMESTAMPTZ,
  last_error TEXT,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  updated_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(facility_id, channel)
);

CREATE INDEX IF NOT EXISTS idx_facility_notification_provider_connections
  ON public.facility_notification_provider_connections(facility_id, channel, status);

ALTER TABLE public.facility_notification_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.facility_notification_provider_connections ENABLE ROW LEVEL SECURITY;

CREATE POLICY "facility notification config access"
ON public.facility_notification_config FOR SELECT TO authenticated
USING (public.has_facility_access(auth.uid(), facility_id));

CREATE POLICY "facility notification config admin manage"
ON public.facility_notification_config FOR ALL TO authenticated
USING (public.has_facility_access(auth.uid(), facility_id) AND public.has_role(auth.uid(),'admin'))
WITH CHECK (public.has_facility_access(auth.uid(), facility_id) AND public.has_role(auth.uid(),'admin'));

CREATE POLICY "facility notification provider access"
ON public.facility_notification_provider_connections FOR SELECT TO authenticated
USING (public.has_facility_access(auth.uid(), facility_id));

CREATE POLICY "facility notification provider admin manage"
ON public.facility_notification_provider_connections FOR ALL TO authenticated
USING (public.has_facility_access(auth.uid(), facility_id) AND public.has_role(auth.uid(),'admin'))
WITH CHECK (public.has_facility_access(auth.uid(), facility_id) AND public.has_role(auth.uid(),'admin'));

CREATE OR REPLACE FUNCTION public.initialize_facility_notification_onboarding(_facility_id UUID)
RETURNS public.facility_notification_config
LANGUAGE plpgsql
SECURITY DEFINER SET search_path=public
AS $$
DECLARE v public.facility_notification_config;
BEGIN
  IF auth.uid() IS NULL OR NOT public.has_role(auth.uid(),'admin') THEN
    RAISE EXCEPTION 'Only administrators may initialize notification onboarding';
  END IF;
  IF NOT public.has_facility_access(auth.uid(), _facility_id) THEN
    RAISE EXCEPTION 'Facility access required';
  END IF;

  INSERT INTO public.facility_notification_config(facility_id,created_by,updated_by)
  VALUES(_facility_id,auth.uid(),auth.uid())
  ON CONFLICT(facility_id) DO UPDATE
    SET updated_by=auth.uid(),updated_at=now()
  RETURNING * INTO v;

  RETURN v;
END;
$$;

REVOKE ALL ON FUNCTION public.initialize_facility_notification_onboarding(UUID) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.initialize_facility_notification_onboarding(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.set_facility_notification_provider(
  _facility_id UUID,
  _channel TEXT,
  _provider TEXT,
  _environment TEXT DEFAULT 'sandbox',
  _secret_reference TEXT DEFAULT NULL,
  _sender_identity TEXT DEFAULT NULL,
  _account_reference TEXT DEFAULT NULL
)
RETURNS public.facility_notification_provider_connections
LANGUAGE plpgsql
SECURITY DEFINER SET search_path=public
AS $$
DECLARE v public.facility_notification_provider_connections;
BEGIN
  IF auth.uid() IS NULL OR NOT public.has_role(auth.uid(),'admin') THEN
    RAISE EXCEPTION 'Only administrators may configure notification providers';
  END IF;
  IF NOT public.has_facility_access(auth.uid(), _facility_id) THEN
    RAISE EXCEPTION 'Facility access required';
  END IF;

  INSERT INTO public.facility_notification_provider_connections(
    facility_id,channel,provider,environment,secret_reference,sender_identity,account_reference,
    status,created_by,updated_by
  )
  VALUES(_facility_id,_channel,_provider,_environment,NULLIF(trim(_secret_reference),''),
         NULLIF(trim(_sender_identity),''),NULLIF(trim(_account_reference),''),
         'configured',auth.uid(),auth.uid())
  ON CONFLICT(facility_id,channel) DO UPDATE SET
    provider=EXCLUDED.provider,environment=EXCLUDED.environment,
    secret_reference=EXCLUDED.secret_reference,sender_identity=EXCLUDED.sender_identity,
    account_reference=EXCLUDED.account_reference,status='configured',
    last_error=NULL,updated_by=auth.uid(),updated_at=now()
  RETURNING * INTO v;

  RETURN v;
END;
$$;

REVOKE ALL ON FUNCTION public.set_facility_notification_provider(UUID,TEXT,TEXT,TEXT,TEXT,TEXT,TEXT) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.set_facility_notification_provider(UUID,TEXT,TEXT,TEXT,TEXT,TEXT,TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.mark_facility_notification_production_ready(_facility_id UUID)
RETURNS public.facility_notification_config
LANGUAGE plpgsql
SECURITY DEFINER SET search_path=public
AS $$
DECLARE v public.facility_notification_config;
BEGIN
  IF auth.uid() IS NULL OR NOT public.has_role(auth.uid(),'admin') THEN
    RAISE EXCEPTION 'Only administrators may approve notification production readiness';
  END IF;
  IF NOT public.has_facility_access(auth.uid(), _facility_id) THEN
    RAISE EXCEPTION 'Facility access required';
  END IF;

  SELECT * INTO v FROM public.facility_notification_config WHERE facility_id=_facility_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Notification onboarding has not been initialized'; END IF;
  IF v.onboarding_status NOT IN ('sandbox_ready','verification_pending') THEN
    RAISE EXCEPTION 'Provider verification is required before production readiness';
  END IF;

  UPDATE public.facility_notification_config
  SET environment='production',enabled=true,rollout_percent=100,
      onboarding_status='production_ready',verified_at=now(),verified_by=auth.uid(),
      updated_by=auth.uid(),updated_at=now()
  WHERE facility_id=_facility_id
  RETURNING * INTO v;
  RETURN v;
END;
$$;

REVOKE ALL ON FUNCTION public.mark_facility_notification_production_ready(UUID) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.mark_facility_notification_production_ready(UUID) TO authenticated;

INSERT INTO public.facility_notification_config(facility_id,created_by,updated_by)
SELECT hf.id,hf.created_by,hf.created_by
FROM public.healthcare_facilities hf
WHERE NOT EXISTS (
  SELECT 1 FROM public.facility_notification_config fnc WHERE fnc.facility_id=hf.id
)
ON CONFLICT(facility_id) DO NOTHING;
