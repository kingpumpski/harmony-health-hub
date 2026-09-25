DO $$
DECLARE c integer;
BEGIN
 ASSERT to_regclass('public.notification_events') IS NOT NULL, 'notification_events missing';
 ASSERT to_regclass('public.notification_templates') IS NOT NULL, 'notification_templates missing';
 ASSERT to_regclass('public.user_notification_preferences') IS NOT NULL, 'user_notification_preferences missing';
 ASSERT to_regclass('public.scheduled_notifications') IS NOT NULL, 'scheduled_notifications missing';
 ASSERT to_regclass('public.notification_delivery_logs') IS NOT NULL, 'notification_delivery_logs missing';
 ASSERT to_regclass('public.notification_audit') IS NOT NULL, 'notification_audit missing';
 ASSERT to_regclass('public.notification_feature_flags') IS NOT NULL, 'notification_feature_flags missing';
 ASSERT to_regclass('public.facility_notification_config') IS NOT NULL, 'facility_notification_config missing';
 ASSERT to_regclass('public.facility_notification_provider_connections') IS NOT NULL, 'facility_notification_provider_connections missing';
 ASSERT EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='scheduled_notifications' AND column_name='facility_id'),'scheduled notification facility scope missing';
 SELECT count(*) INTO c FROM public.notification_events WHERE event_name IN ('appointment_reminder_24h','critical_lab_alert','medication_dose_reminder');
 ASSERT c=3,'core notification events missing';
 SELECT count(*) INTO c FROM public.notification_channels WHERE code IN ('in_app','email','sms','push','whatsapp','voice');
 ASSERT c=6,'channel catalog incomplete';
 ASSERT EXISTS(SELECT 1 FROM pg_indexes WHERE indexname='notification_queue_idempotency_uq'),'queue idempotency index missing';
 ASSERT to_regprocedure('public.initialize_facility_notification_onboarding(uuid)') IS NOT NULL,'facility notification onboarding initializer missing';
 ASSERT to_regprocedure('public.mark_facility_notification_production_ready(uuid)') IS NOT NULL,'facility notification production gate missing';
 ASSERT to_regprocedure('public.verify_facility_notification_provider(uuid,text,text,boolean,text)') IS NOT NULL,'facility notification provider verification function missing';
 ASSERT to_regclass('public.notification_provider_secret_requirements') IS NOT NULL,'notification provider secret requirements catalog missing';
 SELECT count(*) INTO c FROM public.notification_provider_secret_requirements WHERE provider IN ('resend','smtp','fcm','twilio','twilio_whatsapp','twilio_voice');
 ASSERT c >= 20,'notification provider deployment secret catalog incomplete';
END $$;

-- Deterministic facility provider routing contract.
do $$
begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema='public'
      and table_name='facility_notification_provider_connections'
      and column_name='priority'
  ) then
    raise exception 'notification provider priority column is missing';
  end if;
  if not exists (
    select 1 from information_schema.columns
    where table_schema='public'
      and table_name='facility_notification_provider_connections'
      and column_name='is_primary'
  ) then
    raise exception 'notification provider primary flag is missing';
  end if;
  if not exists (
    select 1 from pg_indexes
    where schemaname='public'
      and indexname='facility_notification_provider_primary_uq'
  ) then
    raise exception 'notification provider primary uniqueness boundary is missing';
  end if;
end $$;
