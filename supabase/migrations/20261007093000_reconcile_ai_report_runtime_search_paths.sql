-- Reconcile AI report and patient appointment SECURITY DEFINER runtime paths.
-- These functions intentionally use schema-qualified table/function references for privileged
-- execution. Keep public in the search_path because legacy role predicates in the function
-- bodies resolve public.has_role(...).
BEGIN;

ALTER FUNCTION public.get_ai_report_requests(uuid, integer)
  SET search_path = pg_catalog, public;

ALTER FUNCTION public.create_ai_report_request(uuid, text)
  SET search_path = pg_catalog, public;

ALTER FUNCTION public.complete_ai_report_request(uuid, text, text)
  SET search_path = pg_catalog, public;

ALTER FUNCTION public.create_patient_appointment(uuid, timestamptz, text, text)
  SET search_path = pg_catalog, public;

NOTIFY pgrst, 'reload schema';

COMMIT;
