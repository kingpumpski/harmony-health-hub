-- Keep authorization helpers available to SECURITY DEFINER database workflows,
-- but do not expose arbitrary-user authorization probes through the Data API.
-- Client-facing checks use the current-user helper functions once their
-- canonical definitions have been created by the later authorization migrations.

revoke execute on function public.has_role(uuid, public.app_role) from authenticated, anon, public;
revoke execute on function public.is_clinical_staff(uuid) from authenticated, anon, public;
revoke execute on function public.has_facility_access(uuid, uuid) from authenticated, anon, public;
revoke execute on function public.can_edit_patient_record(uuid) from authenticated, anon, public;
