-- SMTP email provider configuration and tenant-ready onboarding metadata.
-- Secrets are never stored in this migration or in tenant configuration tables.
-- The secret_reference identifies the deployment secret mapping used by the worker.

INSERT INTO public.notification_provider_health(provider,channel)
VALUES ('smtp','email')
ON CONFLICT(provider) DO NOTHING;

UPDATE public.notification_channels
SET provider='smtp'
WHERE code='email' AND COALESCE(current_setting('notification.email_provider', true),'')='smtp';

COMMENT ON TABLE public.facility_notification_provider_connections IS
'Provider connection metadata only. secret_reference points to deployment-managed secrets; credentials must never be stored here.';

COMMENT ON COLUMN public.facility_notification_provider_connections.secret_reference IS
'Reference/name of the deployment secret or external secret-manager entry. The credential value is never stored in the database.';

-- Keep email disabled until the organization/tenant has completed provider verification.
UPDATE public.notification_channels
SET enabled=false
WHERE code='email';
