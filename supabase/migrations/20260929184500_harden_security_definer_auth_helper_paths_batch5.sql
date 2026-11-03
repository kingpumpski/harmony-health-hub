-- Batch 5: harden shared authorization/facility helper and notification SECURITY DEFINER paths.
alter function public.can_edit_patient_record(uuid) set search_path = pg_catalog, public;
alter function public.claim_notification_queue(integer) set search_path = pg_catalog, public;
alter function public.current_user_can_edit_patient_record() set search_path = pg_catalog, public;
DO $current_user_facility_id_search_path$
BEGIN
  IF to_regprocedure('public.current_user_facility_id()') IS NOT NULL THEN
    EXECUTE 'ALTER FUNCTION public.current_user_facility_id() SET search_path = pg_catalog, public';
  ELSE
    RAISE NOTICE 'Skipping current_user_facility_id hardening because the helper is created by a later migration with an empty pinned search_path.';
  END IF;
END;
$current_user_facility_id_search_path$;
alter function public.current_user_has_catalogue_create_permission(text) set search_path = pg_catalog, public;
alter function public.current_user_has_facility_access(uuid) set search_path = pg_catalog, public;
alter function public.current_user_has_role(app_role) set search_path = pg_catalog, public;
alter function public.current_user_is_clinical_staff() set search_path = pg_catalog, public;
