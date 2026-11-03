-- Batch 5: harden shared authorization/facility helper and notification SECURITY DEFINER paths.
alter function public.can_edit_patient_record(uuid) set search_path = pg_catalog, public;
alter function public.claim_notification_queue(integer) set search_path = pg_catalog, public;
alter function public.current_user_can_edit_patient_record() set search_path = pg_catalog, public;
DO $current_user_facility_id_search_path$
DECLARE
  helper_function regprocedure := to_regprocedure('public.current_user_facility_id()');
  helper_config text[];
BEGIN
  IF helper_function IS NOT NULL THEN
    SELECT p.proconfig
      INTO helper_config
    FROM pg_proc p
    WHERE p.oid = helper_function::oid;

    -- Preserve any existing function-level search_path, especially the empty
    -- path used by the production helper and by its later migration definition.
    IF NOT EXISTS (
      SELECT 1
      FROM unnest(COALESCE(helper_config, ARRAY[]::text[])) AS setting
      WHERE setting LIKE 'search_path=%'
    ) THEN
      EXECUTE 'ALTER FUNCTION public.current_user_facility_id() SET search_path = pg_catalog, public';
    END IF;
  END IF;
END;
$current_user_facility_id_search_path$;
alter function public.current_user_has_catalogue_create_permission(text) set search_path = pg_catalog, public;
alter function public.current_user_has_facility_access(uuid) set search_path = pg_catalog, public;
alter function public.current_user_has_role(app_role) set search_path = pg_catalog, public;
alter function public.current_user_is_clinical_staff() set search_path = pg_catalog, public;
