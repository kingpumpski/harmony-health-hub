-- Batch 5: harden shared authorization/facility helper and notification SECURITY DEFINER paths.
alter function public.can_edit_patient_record(uuid) set search_path = pg_catalog, public;
alter function public.claim_notification_queue(integer) set search_path = pg_catalog, public;
alter function public.current_user_can_edit_patient_record() set search_path = pg_catalog, public;
-- The production baseline already defines this helper, but a clean local replay
-- reaches Batch 5 before the canonical local definition later in the chain.
-- Do not weaken an already-empty search_path; defer creation to the later
-- canonical facility-context migration when the helper does not yet exist.
DO $batch5_facility_helper$
DECLARE
  v_function regprocedure := to_regprocedure('public.current_user_facility_id()');
  v_config text[];
BEGIN
  IF v_function IS NOT NULL THEN
    SELECT p.proconfig INTO v_config
    FROM pg_catalog.pg_proc p
    WHERE p.oid = v_function;

    IF NOT COALESCE(v_config @> ARRAY['search_path=""'], false) THEN
      EXECUTE 'ALTER FUNCTION public.current_user_facility_id() SET search_path = pg_catalog, public';
    END IF;
  END IF;
END;
$batch5_facility_helper$;
alter function public.current_user_has_catalogue_create_permission(text) set search_path = pg_catalog, public;
alter function public.current_user_has_facility_access(uuid) set search_path = pg_catalog, public;
alter function public.current_user_has_role(app_role) set search_path = pg_catalog, public;
alter function public.current_user_is_clinical_staff() set search_path = pg_catalog, public;
