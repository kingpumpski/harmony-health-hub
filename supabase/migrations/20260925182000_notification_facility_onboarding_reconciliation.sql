-- Notification onboarding reconciliation.
-- Keeps provider secrets out of Postgres; stores only secret references and operational metadata.
-- Facility creation initializes notification onboarding so configuration belongs to the organization/facility lifecycle.

CREATE TABLE IF NOT EXISTS public.facility_notification_config (
  facility_id UUID PRIMARY KEY REFERENCES public.healthcare_facilities(id) ON DELETE CASCADE,
  environment TEXT NOT NULL DEFAULT 'sandbox' CHECK (environment IN ('sandbox','test','production')),
  enabled BOOLEAN NOT NULL DEFAULT true,
  default_locale TEXT NOT NULL DEFAULT 'en-GH',
  default_timezone TEXT NOT NULL DEFAULT 'Africa/Accra',
  quiet_hours_start TIME NOT NULL DEFAULT '22:00',
  quiet_hours_end TIME NOT NULL DEFAULT '07:00',
  enabled_channels JSONB NOT NULL DEFAULT '{"in_app":true,"email":false,"sms":false,"push":false,"whatsapp":false,"voice":false}'::jsonb,
  sender_config JSONB NOT NULL DEFAULT '{}'::jsonb,
  webhook_config JSONB NOT NULL DEFAULT '{}'::jsonb,
  consent_policy JSONB NOT NULL DEFAULT '{"external_channels_require_consent":true,"critical_override":true}'::jsonb,
  rollout_percent INTEGER NOT NULL DEFAULT 100 CHECK (rollout_percent BETWEEN 0 AND 100),
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
  UNIQUE(facility_id, channel, environment)
);

-- Reconcile the previously shipped onboarding schema if it has already been applied to a target database.
ALTER TABLE public.facility_notification_config
  ADD COLUMN IF NOT EXISTS consent_policy JSONB NOT NULL DEFAULT '{"external_channels_require_consent":true,"critical_override":true}'::jsonb,
  ADD COLUMN IF NOT EXISTS rollout_percent INTEGER NOT NULL DEFAULT 100,
  ADD COLUMN IF NOT EXISTS kill_switch BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS onboarding_status TEXT NOT NULL DEFAULT 'not_started',
  ADD COLUMN IF NOT EXISTS verified_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS verified_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS updated_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();

ALTER TABLE public.facility_notification_provider_connections
  ADD COLUMN IF NOT EXISTS environment TEXT NOT NULL DEFAULT 'sandbox',
  ADD COLUMN IF NOT EXISTS metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS last_verified_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS last_error TEXT,
  ADD COLUMN IF NOT EXISTS created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS updated_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();

CREATE UNIQUE INDEX IF NOT EXISTS facility_notification_provider_connections_env_uq
  ON public.facility_notification_provider_connections(facility_id,channel,environment);

DROP POLICY IF EXISTS "facility notification config scoped read" ON public.facility_notification_config;
DROP POLICY IF EXISTS "facility notification config admin update" ON public.facility_notification_config;
DROP POLICY IF EXISTS "facility notification config access" ON public.facility_notification_config;
DROP POLICY IF EXISTS "facility notification config admin manage" ON public.facility_notification_config;
DROP POLICY IF EXISTS "facility notification provider admin read" ON public.facility_notification_provider_connections;
DROP POLICY IF EXISTS "facility notification provider admin update" ON public.facility_notification_provider_connections;
DROP POLICY IF EXISTS "facility notification provider access" ON public.facility_notification_provider_connections;
DROP POLICY IF EXISTS "facility notification provider admin manage" ON public.facility_notification_provider_connections;

ALTER TABLE public.scheduled_notifications
  ADD COLUMN IF NOT EXISTS facility_id UUID REFERENCES public.healthcare_facilities(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_scheduled_notifications_facility_due
  ON public.scheduled_notifications(facility_id,status,run_at);

ALTER TABLE public.facility_notification_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.facility_notification_provider_connections ENABLE ROW LEVEL SECURITY;

CREATE POLICY "facility notification config scoped read"
  ON public.facility_notification_config FOR SELECT TO authenticated
  USING (public.has_facility_access(auth.uid(),facility_id));

CREATE POLICY "facility notification config admin update"
  ON public.facility_notification_config FOR UPDATE TO authenticated
  USING (public.has_role(auth.uid(),'admin') AND public.has_facility_access(auth.uid(),facility_id))
  WITH CHECK (public.has_role(auth.uid(),'admin') AND public.has_facility_access(auth.uid(),facility_id));

CREATE POLICY "facility notification provider admin read"
  ON public.facility_notification_provider_connections FOR SELECT TO authenticated
  USING (public.has_role(auth.uid(),'admin') AND public.has_facility_access(auth.uid(),facility_id));

CREATE POLICY "facility notification provider admin update"
  ON public.facility_notification_provider_connections FOR ALL TO authenticated
  USING (public.has_role(auth.uid(),'admin') AND public.has_facility_access(auth.uid(),facility_id))
  WITH CHECK (public.has_role(auth.uid(),'admin') AND public.has_facility_access(auth.uid(),facility_id));

REVOKE ALL ON public.facility_notification_provider_connections FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.facility_notification_provider_connections TO authenticated;

CREATE OR REPLACE FUNCTION public.initialize_facility_notification_onboarding(_facility_id UUID)
RETURNS public.facility_notification_config
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v public.facility_notification_config;
BEGIN
  IF auth.uid() IS NULL OR NOT public.has_role(auth.uid(),'admin') OR NOT public.has_facility_access(auth.uid(),_facility_id) THEN
    RAISE EXCEPTION 'Facility notification onboarding requires administrator facility access';
  END IF;
  INSERT INTO public.facility_notification_config(facility_id,created_by,updated_by)
  VALUES(_facility_id,auth.uid(),auth.uid())
  ON CONFLICT(facility_id) DO UPDATE SET updated_at=now(),updated_by=auth.uid()
  RETURNING * INTO v;
  RETURN v;
END $$;

CREATE OR REPLACE FUNCTION public.set_facility_notification_provider(
  _facility_id UUID,_channel TEXT,_provider TEXT,_environment TEXT DEFAULT 'sandbox',
  _secret_reference TEXT DEFAULT NULL,_sender_identity TEXT DEFAULT NULL,_account_reference TEXT DEFAULT NULL,
  _metadata JSONB DEFAULT '{}'::jsonb
)
RETURNS public.facility_notification_provider_connections
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v public.facility_notification_provider_connections;
BEGIN
  IF auth.uid() IS NULL OR NOT public.has_role(auth.uid(),'admin') OR NOT public.has_facility_access(auth.uid(),_facility_id) THEN
    RAISE EXCEPTION 'Facility notification provider configuration requires administrator facility access';
  END IF;
  IF _secret_reference IS NOT NULL AND length(_secret_reference) > 255 THEN RAISE EXCEPTION 'Secret reference is too long'; END IF;
  INSERT INTO public.facility_notification_provider_connections(
    facility_id,channel,provider,environment,secret_reference,sender_identity,account_reference,status,metadata,created_by,updated_by
  ) VALUES(_facility_id,_channel,_provider,_environment,_secret_reference,_sender_identity,_account_reference,
    CASE WHEN _secret_reference IS NULL THEN 'not_configured' ELSE 'configured' END,COALESCE(_metadata,'{}'::jsonb),auth.uid(),auth.uid())
  ON CONFLICT(facility_id,channel,environment) DO UPDATE SET
    provider=EXCLUDED.provider,secret_reference=EXCLUDED.secret_reference,sender_identity=EXCLUDED.sender_identity,
    account_reference=EXCLUDED.account_reference,status=EXCLUDED.status,metadata=EXCLUDED.metadata,
    updated_by=auth.uid(),updated_at=now()
  RETURNING * INTO v;
  RETURN v;
END $$;

CREATE OR REPLACE FUNCTION public.mark_facility_notification_production_ready(_facility_id UUID)
RETURNS public.facility_notification_config
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v public.facility_notification_config;
BEGIN
  IF auth.uid() IS NULL OR NOT public.has_role(auth.uid(),'admin') OR NOT public.has_facility_access(auth.uid(),_facility_id) THEN
    RAISE EXCEPTION 'Facility notification production readiness requires administrator facility access';
  END IF;
  IF NOT EXISTS(
    SELECT 1 FROM public.facility_notification_provider_connections
    WHERE facility_id=_facility_id AND environment IN ('test','production') AND status='verified'
  ) THEN
    RAISE EXCEPTION 'At least one verified external notification provider is required';
  END IF;
  UPDATE public.facility_notification_config
  SET environment='production',enabled=true,rollout_percent=100,kill_switch=false,
      onboarding_status='production_ready',verified_at=now(),verified_by=auth.uid(),updated_by=auth.uid(),updated_at=now()
  WHERE facility_id=_facility_id
  RETURNING * INTO v;
  IF v.facility_id IS NULL THEN RAISE EXCEPTION 'Facility notification configuration not found'; END IF;
  RETURN v;
END $$;

-- Existing facilities receive a safe in-app-first onboarding record. External channels stay disabled.
INSERT INTO public.facility_notification_config(facility_id)
SELECT hf.id FROM public.healthcare_facilities hf
ON CONFLICT(facility_id) DO NOTHING;

-- Facility creation is the lifecycle entry point: seed notification onboarding immediately after the
-- existing facility/report setup, without exposing provider secrets or enabling external delivery.
CREATE OR REPLACE FUNCTION public.create_reports_facility(
  _name TEXT,_facility_code TEXT DEFAULT NULL,_facility_type TEXT DEFAULT 'district_hospital',
  _district TEXT DEFAULT NULL,_region TEXT DEFAULT NULL,_dhims2_uid TEXT DEFAULT NULL
)
RETURNS public.healthcare_facilities
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v public.healthcare_facilities;
BEGIN
  IF auth.uid() IS NULL OR NOT public.has_role(auth.uid(),'admin') THEN RAISE EXCEPTION 'Only administrators may create healthcare facilities'; END IF;
  IF NULLIF(trim(_name),'') IS NULL THEN RAISE EXCEPTION 'Facility name is required'; END IF;
  INSERT INTO public.healthcare_facilities(name,facility_code,facility_type,district,region,dhims2_uid,created_by)
  VALUES(trim(_name),NULLIF(trim(_facility_code),''),_facility_type,NULLIF(trim(_district),''),NULLIF(trim(_region),''),NULLIF(trim(_dhims2_uid),''),auth.uid())
  RETURNING * INTO v;
  INSERT INTO public.facility_memberships(facility_id,user_id)
  VALUES(v.id,auth.uid()) ON CONFLICT(facility_id,user_id) DO UPDATE SET is_active=true;
  PERFORM public.seed_facility_reports(v.id);
  INSERT INTO public.facility_notification_config(facility_id,created_by,updated_by)
  VALUES(v.id,auth.uid(),auth.uid()) ON CONFLICT(facility_id) DO NOTHING;
  RETURN v;
END $$;

REVOKE ALL ON FUNCTION public.initialize_facility_notification_onboarding(UUID) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.initialize_facility_notification_onboarding(UUID) TO authenticated;
REVOKE ALL ON FUNCTION public.set_facility_notification_provider(UUID,TEXT,TEXT,TEXT,TEXT,TEXT,TEXT,JSONB) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.set_facility_notification_provider(UUID,TEXT,TEXT,TEXT,TEXT,TEXT,TEXT,JSONB) TO authenticated;
REVOKE ALL ON FUNCTION public.mark_facility_notification_production_ready(UUID) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.mark_facility_notification_production_ready(UUID) TO authenticated;
REVOKE ALL ON FUNCTION public.create_reports_facility(TEXT,TEXT,TEXT,TEXT,TEXT,TEXT) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.create_reports_facility(TEXT,TEXT,TEXT,TEXT,TEXT,TEXT) TO authenticated;
