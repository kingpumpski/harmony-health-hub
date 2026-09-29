-- Batch 10: harden notification/facility/report SECURITY DEFINER paths.
-- Search-path hardening only; signatures and authorization semantics are preserved.
ALTER FUNCTION public.enqueue_notification_v2(text,uuid,jsonb,text,jsonb,text,timestamp with time zone,text,uuid,text,text,uuid) SET search_path = pg_catalog, public;
ALTER FUNCTION public.ensure_notification_preferences(uuid) SET search_path = pg_catalog, public;
ALTER FUNCTION public.erase_notification_history(uuid) SET search_path = pg_catalog, public;
ALTER FUNCTION public.initialize_facility_notification_onboarding(uuid) SET search_path = pg_catalog, public;
ALTER FUNCTION public.mark_facility_notification_production_ready(uuid) SET search_path = pg_catalog, public;
ALTER FUNCTION public.mark_notification_read(uuid) SET search_path = pg_catalog, public;
ALTER FUNCTION public.mark_report_submissions_submitted(uuid[]) SET search_path = pg_catalog, public;
ALTER FUNCTION public.mark_video_session_paid(uuid) SET search_path = pg_catalog, public;
ALTER FUNCTION public.record_notification_consent(text,text,boolean,text,text,inet) SET search_path = pg_catalog, public;
ALTER FUNCTION public.recover_stale_report_run(uuid,integer) SET search_path = pg_catalog, public;
ALTER FUNCTION public.register_notification_device(text,text,text,text) SET search_path = pg_catalog, public;
ALTER FUNCTION public.revoke_notification_device(text) SET search_path = pg_catalog, public;
ALTER FUNCTION public.seed_facility_reports(uuid) SET search_path = pg_catalog, public;
ALTER FUNCTION public.set_facility_routing_mode(text) SET search_path = pg_catalog, public;
ALTER FUNCTION public.set_my_active_facility(uuid) SET search_path = pg_catalog, public;
ALTER FUNCTION public.sync_overdue_report_submissions(uuid,date,date) SET search_path = pg_catalog, public;
ALTER FUNCTION public.upsert_my_staff_signature(text) SET search_path = pg_catalog, public;
ALTER FUNCTION public.upsert_report_submission_tracking(uuid,uuid,date,date,date,jsonb) SET search_path = pg_catalog, public;
ALTER FUNCTION public.verify_facility_notification_provider(uuid,text,text,boolean,text) SET search_path = pg_catalog, public;