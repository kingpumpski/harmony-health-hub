-- Platform superuser authorization and facility-directory compatibility are part of the
-- forward migration history. This follow-up preserves the canonical facility RPC while
-- keeping the legacy misspelling as a safe authenticated-only wrapper.
create or replace function public.platform_list_facilitys()
returns table(id uuid,name text,facility_code text,facility_type text,district text,region text,is_active boolean,created_at timestamptz)
language plpgsql stable security definer set search_path=''
as $function$
begin
  if not exists (
    select 1 from public.user_roles ur
    where ur.user_id=(select auth.uid())
      and ur.role='system_superuser'::public.app_role
  ) then
    raise exception 'Only system super administrators may view platform facilities';
  end if;
  return query select * from public.platform_list_facilities();
end;
$function$;
revoke all on function public.platform_list_facilitys() from public,anon,authenticated;
grant execute on function public.platform_list_facilitys() to authenticated;
notify pgrst,'reload schema';
