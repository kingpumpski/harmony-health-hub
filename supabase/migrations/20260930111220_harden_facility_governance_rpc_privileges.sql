revoke all on function public.approve_facility_data_sharing_agreement(uuid) from public,anon;
grant execute on function public.approve_facility_data_sharing_agreement(uuid) to authenticated;
revoke all on function public.create_facility_data_sharing_agreement(uuid,uuid,text,timestamptz,timestamptz,text[]) from public,anon;
grant execute on function public.create_facility_data_sharing_agreement(uuid,uuid,text,timestamptz,timestamptz,text[]) to authenticated;
revoke all on function public.revoke_facility_data_sharing_agreement(uuid,text) from public,anon;
grant execute on function public.revoke_facility_data_sharing_agreement(uuid,text) to authenticated;
revoke all on function public.set_user_facility_context(uuid,uuid) from public,anon;
grant execute on function public.set_user_facility_context(uuid,uuid) to authenticated;