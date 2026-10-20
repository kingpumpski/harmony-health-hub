-- Keep authorization helpers available to SECURITY DEFINER database workflows,
-- but do not expose arbitrary-user authorization probes through the Data API.
-- Client-facing checks use the current-user helper functions instead.

revoke execute on function public.has_role(uuid, public.app_role) from authenticated, anon, public;
revoke execute on function public.is_clinical_staff(uuid) from authenticated, anon, public;
revoke execute on function public.has_facility_access(uuid, uuid) from authenticated, anon, public;
revoke execute on function public.can_edit_patient_record(uuid) from authenticated, anon, public;

DO $current_user_role_helper_guard$
BEGIN
  IF to_regprocedure('public.current_user_has_role(public.app_role)') IS NOT NULL THEN
    EXECUTE 'REVOKE EXECUTE ON FUNCTION public.current_user_has_role(public.app_role) FROM anon, public';
  END IF;
END;
$current_user_role_helper_guard$;
DO $current_user_other_helpers_guard$
BEGIN
  IF pg_catalog.to_regprocedure('public.current_user_is_clinical_staff()') IS NOT NULL THEN
    EXECUTE 'REVOKE EXECUTE ON FUNCTION public.current_user_is_clinical_staff() FROM anon, public';
  END IF;
  IF pg_catalog.to_regprocedure('public.current_user_can_edit_patient_record()') IS NOT NULL THEN
    EXECUTE 'REVOKE EXECUTE ON FUNCTION public.current_user_can_edit_patient_record() FROM anon, public';
  END IF;
END;
$current_user_other_helpers_guard$;
