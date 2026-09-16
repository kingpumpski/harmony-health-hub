-- Keep authorization helpers available to SECURITY DEFINER database workflows,
-- but do not expose arbitrary-user authorization probes through the Data API.
-- Client-facing checks use the current-user helper functions instead.

revoke execute on function public.has_role(uuid, public.app_role) from authenticated, anon, public;
revoke execute on function public.is_clinical_staff(uuid) from authenticated, anon, public;
revoke execute on function public.has_facility_access(uuid, uuid) from authenticated, anon, public;
revoke execute on function public.can_edit_patient_record(uuid) from authenticated, anon, public;

revoke execute on function public.current_user_has_role(public.app_role) from anon, public;
revoke execute on function public.current_user_is_clinical_staff() from anon, public;
revoke execute on function public.current_user_can_edit_patient_record() from anon, public;
