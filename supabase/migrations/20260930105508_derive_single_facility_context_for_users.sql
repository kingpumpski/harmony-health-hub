create or replace function public.get_user_facilities()
returns table(facility_id uuid,facility_name text,facility_code text,facility_type text,is_active boolean)
language plpgsql stable security definer set search_path='pg_catalog','public'
as $$
declare uid uuid:=auth.uid(); v_facility uuid:=public.current_user_facility_id();
begin
 if uid is null then raise exception 'Authentication required'; end if;
 if public.current_user_has_role('system_superuser') then
  return query select hf.id,hf.name,hf.facility_code,hf.facility_type,hf.is_active from public.healthcare_facilities hf where hf.is_active=true order by hf.name,hf.id;
 else
  return query select hf.id,hf.name,hf.facility_code,hf.facility_type,hf.is_active from public.healthcare_facilities hf where hf.is_active=true and hf.id=v_facility limit 1;
 end if;
end; $$;
revoke all on function public.get_user_facilities() from public,anon;
grant execute on function public.get_user_facilities() to authenticated;