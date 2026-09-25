-- RLS policies on facility_report_config invoke authorization helpers.
-- Keep the arbitrary-user helpers internal; this grant was required by the live policy
-- boundary before the scoped wrappers were introduced in the follow-up migration.
grant execute on function public.has_facility_access(uuid, uuid) to authenticated;
grant execute on function public.has_role(uuid, public.app_role) to authenticated;
