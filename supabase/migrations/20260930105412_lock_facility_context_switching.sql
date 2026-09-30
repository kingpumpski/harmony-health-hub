revoke all on function public.set_active_facility_context(uuid) from public,anon,authenticated;
revoke all on function public.get_user_facilities() from public,anon,authenticated;
grant execute on function public.get_user_facilities() to authenticated;
comment on function public.set_active_facility_context(uuid) is 'Retained for historical compatibility but intentionally not callable by application users. Facility context is server-derived from provisioned membership.';