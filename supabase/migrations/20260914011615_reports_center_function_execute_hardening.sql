REVOKE ALL ON FUNCTION public.create_reports_facility(text,text,text,text,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_reports_facility(text,text,text,text,text,text) TO authenticated;

REVOKE ALL ON FUNCTION public.seed_facility_reports(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.seed_facility_reports(uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.recover_stale_report_run(uuid,integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.recover_stale_report_run(uuid,integer) TO authenticated;

REVOKE ALL ON FUNCTION public.upsert_report_submission_tracking(uuid,uuid,date,date,date,jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.upsert_report_submission_tracking(uuid,uuid,date,date,date,jsonb) TO authenticated;

REVOKE ALL ON FUNCTION public.sync_overdue_report_submissions(uuid,date,date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.sync_overdue_report_submissions(uuid,date,date) TO authenticated;

REVOKE ALL ON FUNCTION public.mark_report_submissions_submitted(uuid[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.mark_report_submissions_submitted(uuid[]) TO authenticated;

REVOKE ALL ON FUNCTION public.has_facility_access(uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.has_facility_access(uuid,uuid) TO authenticated;
