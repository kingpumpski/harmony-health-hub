-- Notification onboarding configuration catalog.
-- Stores configuration metadata and a non-secret checklist of deployment values.
-- Secret values themselves remain in the approved deployment secret manager / Supabase Edge Function secrets.

ALTER TABLE public.facility_notification_config
  ADD COLUMN IF NOT EXISTS branding JSONB NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS provider_defaults JSONB NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS delivery_policy JSONB NOT NULL DEFAULT '{
    "retry_backoff_seconds":[10,30,120,600,3600],
    "max_attempts":5,
    "fallback_enabled":true,
    "critical_bypass_quiet_hours":true,
    "critical_external_consent_override":true,
    "dedupe_window_seconds":86400
  }'::jsonb,
  ADD COLUMN IF NOT EXISTS webhook_policy JSONB NOT NULL DEFAULT '{
    "signed_webhooks_required":true,
    "idempotency_required":true,
    "public_callback_configured":false
  }'::jsonb,
  ADD COLUMN IF NOT EXISTS compliance_policy JSONB NOT NULL DEFAULT '{
    "external_channels_require_consent":true,
    "minimum_necessary_content":true,
    "audit_enabled":true,
    "history_erasure_enabled":true
  }'::jsonb,
  ADD COLUMN IF NOT EXISTS operational_contacts JSONB NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS deployment_secret_namespace TEXT,
  ADD COLUMN IF NOT EXISTS production_approved_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS production_approved_by UUID REFERENCES auth.users(id) ON DELETE SET NULL;

CREATE TABLE IF NOT EXISTS public.notification_provider_secret_requirements (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  provider TEXT NOT NULL,
  channel TEXT NOT NULL CHECK (channel IN ('email','sms','push','whatsapp','voice')),
  secret_name TEXT NOT NULL,
  environment TEXT NOT NULL DEFAULT 'all' CHECK (environment IN ('all','sandbox','test','production')),
  required BOOLEAN NOT NULL DEFAULT true,
  description TEXT NOT NULL,
  secret_reference_example TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(provider,channel,secret_name,environment)
);

ALTER TABLE public.notification_provider_secret_requirements ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "notification secret requirements authenticated read" ON public.notification_provider_secret_requirements;
CREATE POLICY "notification secret requirements authenticated read"
  ON public.notification_provider_secret_requirements FOR SELECT TO authenticated USING (true);
REVOKE ALL ON public.notification_provider_secret_requirements FROM PUBLIC, anon;
GRANT SELECT ON public.notification_provider_secret_requirements TO authenticated;

INSERT INTO public.notification_provider_secret_requirements
(provider,channel,secret_name,environment,required,description,secret_reference_example)
VALUES
('resend','email','RESEND_API_KEY','all',true,'Resend API credential used by the asynchronous email adapter','supabase:RESEND_API_KEY'),
('resend','email','RESEND_FROM_EMAIL','all',true,'Verified sender identity for Resend email delivery','supabase:RESEND_FROM_EMAIL'),
('resend','email','RESEND_WEBHOOK_SECRET','all',true,'Signing secret used to verify Resend webhook events','supabase:RESEND_WEBHOOK_SECRET'),
('resend','email','NOTIFICATION_WEBHOOK_PUBLIC_URL','all',true,'Public HTTPS callback URL for notification provider webhooks','deployment:NOTIFICATION_WEBHOOK_PUBLIC_URL'),
('smtp','email','NOTIFICATION_EMAIL_PROVIDER','all',true,'Set to smtp when SMTP is the selected email adapter','supabase:NOTIFICATION_EMAIL_PROVIDER'),
('smtp','email','SMTP_HOST','all',true,'SMTP server hostname','supabase:SMTP_HOST'),
('smtp','email','SMTP_PORT','all',true,'SMTP server TCP port, normally 465 or 587','supabase:SMTP_PORT'),
('smtp','email','SMTP_SECURE','all',true,'Whether the SMTP connection uses implicit TLS','supabase:SMTP_SECURE'),
('smtp','email','SMTP_USERNAME','all',true,'SMTP authentication username','supabase:SMTP_USERNAME'),
('smtp','email','SMTP_PASSWORD','all',true,'SMTP authentication password or app password','supabase:SMTP_PASSWORD'),
('smtp','email','SMTP_FROM_EMAIL','all',true,'Verified sender mailbox/address','supabase:SMTP_FROM_EMAIL'),
('smtp','email','SMTP_FROM_NAME','all',false,'Display name for outbound messages','supabase:SMTP_FROM_NAME'),
('fcm','push','FCM_PROJECT_ID','all',true,'Firebase project identifier','supabase:FCM_PROJECT_ID'),
('fcm','push','FCM_SERVICE_ACCOUNT_JSON','all',true,'Firebase service-account JSON for FCM HTTP v1 server authentication','supabase:FCM_SERVICE_ACCOUNT_JSON'),
('twilio','sms','TWILIO_ACCOUNT_SID','all',true,'Twilio account identifier','supabase:TWILIO_ACCOUNT_SID'),
('twilio','sms','TWILIO_AUTH_TOKEN','all',true,'Twilio authentication token','supabase:TWILIO_AUTH_TOKEN'),
('twilio','sms','TWILIO_SMS_FROM','all',true,'Twilio SMS sender number','supabase:TWILIO_SMS_FROM'),
('twilio','sms','NOTIFICATION_WEBHOOK_PUBLIC_URL','all',false,'Public HTTPS callback URL for SMS delivery status callbacks','deployment:NOTIFICATION_WEBHOOK_PUBLIC_URL'),
('twilio_whatsapp','whatsapp','TWILIO_ACCOUNT_SID','all',true,'Twilio account identifier','supabase:TWILIO_ACCOUNT_SID'),
('twilio_whatsapp','whatsapp','TWILIO_AUTH_TOKEN','all',true,'Twilio authentication token','supabase:TWILIO_AUTH_TOKEN'),
('twilio_whatsapp','whatsapp','TWILIO_WHATSAPP_FROM','all',true,'Twilio WhatsApp sender identity','supabase:TWILIO_WHATSAPP_FROM'),
('twilio_whatsapp','whatsapp','TWILIO_WHATSAPP_CONTENT_SID','sandbox',true,'Approved Twilio WhatsApp Sandbox/test template content SID','supabase:TWILIO_WHATSAPP_CONTENT_SID'),
('twilio_whatsapp','whatsapp','NOTIFICATION_WEBHOOK_PUBLIC_URL','all',false,'Public HTTPS callback URL for WhatsApp delivery status callbacks','deployment:NOTIFICATION_WEBHOOK_PUBLIC_URL'),
('twilio_voice','voice','TWILIO_ACCOUNT_SID','all',true,'Twilio account identifier','supabase:TWILIO_ACCOUNT_SID'),
('twilio_voice','voice','TWILIO_AUTH_TOKEN','all',true,'Twilio authentication token','supabase:TWILIO_AUTH_TOKEN'),
('twilio_voice','voice','TWILIO_VOICE_FROM','all',true,'Twilio voice caller ID','supabase:TWILIO_VOICE_FROM'),
('twilio_voice','voice','TWILIO_VOICE_TWIML_URL','all',true,'HTTPS TwiML URL controlling critical voice notifications','supabase:TWILIO_VOICE_TWIML_URL'),
('twilio_voice','voice','NOTIFICATION_WEBHOOK_PUBLIC_URL','all',false,'Public HTTPS callback URL for voice status callbacks','deployment:NOTIFICATION_WEBHOOK_PUBLIC_URL')
ON CONFLICT(provider,channel,secret_name,environment) DO UPDATE SET
  required=EXCLUDED.required,description=EXCLUDED.description,secret_reference_example=EXCLUDED.secret_reference_example;

COMMENT ON TABLE public.notification_provider_secret_requirements IS
'Non-secret onboarding catalog. It tells administrators which deployment keys/tokens/configuration values must be supplied; it never stores their values.';

COMMENT ON COLUMN public.facility_notification_config.deployment_secret_namespace IS
'Non-secret namespace/prefix identifying the approved deployment secret boundary for this facility.';

UPDATE public.facility_notification_config
SET delivery_policy=COALESCE(delivery_policy,'{}'::jsonb) ||
  '{"retry_backoff_seconds":[10,30,120,600,3600],"max_attempts":5,"fallback_enabled":true}'::jsonb
WHERE delivery_policy IS NULL OR delivery_policy='{}'::jsonb;
