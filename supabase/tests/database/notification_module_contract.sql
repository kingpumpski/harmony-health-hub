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
 SELECT count(*) INTO c FROM public.notification_events WHERE event_name IN ('appointment_reminder_24h','critical_lab_alert','medication_dose_reminder');
 ASSERT c=3,'core notification events missing';
 SELECT count(*) INTO c FROM public.notification_channels WHERE code IN ('in_app','email','sms','push','whatsapp','voice');
 ASSERT c=6,'channel catalog incomplete';
 ASSERT EXISTS(SELECT 1 FROM pg_indexes WHERE indexname='notification_queue_idempotency_uq'),'queue idempotency index missing';
END $$;