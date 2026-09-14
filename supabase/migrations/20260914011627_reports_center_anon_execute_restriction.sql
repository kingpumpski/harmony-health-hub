REVOKE EXECUTE ON FUNCTION public.create_reports_facility(text,text,text,text,text,text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.seed_facility_reports(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.recover_stale_report_run(uuid,integer) FROM anon;
REVOKE EXECUTE ON FUNCTION public.upsert_report_submission_tracking(uuid,uuid,date,date,date,jsonb) FROM anon;
REVOKE EXECUTE ON FUNCTION public.sync_overdue_report_submissions(uuid,date,date) FROM anon;
REVOKE EXECUTE ON FUNCTION public.mark_report_submissions_submitted(uuid[]) FROM anon;
REVOKE EXECUTE ON FUNCTION public.has_facility_access(uuid,uuid) FROM anon;
