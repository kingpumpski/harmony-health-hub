-- Batch 10: harden notification/facility/report SECURITY DEFINER paths.
-- Search-path hardening only; signatures and authorization semantics are preserved.
--
-- Some functions are supplied by the production baseline or later local
-- migrations. Harden only definitions present at this point in a clean replay,
-- and preserve any function that already has the empty search_path.
DO $batch10_notification_facility_paths$
DECLARE
  v_signature text;
  v_function regprocedure;
  v_config text[];
BEGIN
  FOR v_signature IN
    SELECT signature
    FROM (VALUES
      ('public.enqueue_notification_v2(text,uuid,jsonb,text,jsonb,text,timestamp with time zone,text,uuid,text,text,uuid)'),
      ('public.ensure_notification_preferences(uuid)'),
      ('public.erase_notification_history(uuid)'),
      ('public.initialize_facility_notification_onboarding(uuid)'),
      ('public.mark_facility_notification_production_ready(uuid)'),
      ('public.mark_notification_read(uuid)'),
      ('public.mark_report_submissions_submitted(uuid[])'),
      ('public.mark_video_session_paid(uuid)'),
      ('public.record_notification_consent(text,text,boolean,text,text,inet)'),
      ('public.recover_stale_report_run(uuid,integer)'),
      ('public.register_notification_device(text,text,text,text)'),
      ('public.revoke_notification_device(text)'),
      ('public.seed_facility_reports(uuid)'),
      ('public.set_facility_routing_mode(text)'),
      ('public.set_my_active_facility(uuid)'),
      ('public.sync_overdue_report_submissions(uuid,date,date)'),
      ('public.upsert_my_staff_signature(text)'),
      ('public.upsert_report_submission_tracking(uuid,uuid,date,date,date,jsonb)'),
      ('public.verify_facility_notification_provider(uuid,text,text,boolean,text)')
    ) AS signatures(signature)
  LOOP
    v_function := pg_catalog.to_regprocedure(v_signature);
    IF v_function IS NOT NULL THEN
      SELECT p.proconfig INTO v_config
      FROM pg_catalog.pg_proc p
      WHERE p.oid = v_function;

      IF NOT COALESCE(v_config @> ARRAY['search_path=""'], false) THEN
        EXECUTE pg_catalog.format(
          'ALTER FUNCTION %s SET search_path = pg_catalog, public',
          v_function
        );
      END IF;
    END IF;
  END LOOP;
END;
$batch10_notification_facility_paths$;
