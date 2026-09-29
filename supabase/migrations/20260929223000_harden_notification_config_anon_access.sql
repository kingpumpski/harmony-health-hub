-- Least-privilege hardening: facility notification configuration is never a public/anonymous API surface.
revoke all on table public.facility_notification_config from anon;
