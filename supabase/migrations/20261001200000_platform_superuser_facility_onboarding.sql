-- Platform Superuser facility onboarding control plane.
-- A system_superuser manages platform facilities without inheriting a facility membership.

create or replace function public.platform_create_facility(
  _name text,
  _facility_code text default null,
  _facility_type text default 'district_hospital',
  _district text default null,
  _region text default null,
  _dhims2_uid text default null
)
returns public.healthcare_facilities
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
  v_facility public.healthcare_facilities;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if not exists (
    select 1 from public.user_roles ur
    where ur.user_id=v_user and ur.role='system_superuser'::public.app_role
  ) then raise exception 'Only system super administrators may onboard facilities'; end if;
  if nullif(btrim(coalesce(_name,'')),'') is null then raise exception 'Facility name is required'; end if;
  if _facility_type not in ('chps_compound','health_centre','district_hospital','regional_hospital','teaching_hospital','specialist_hospital','polyclinic','clinic','maternity_home','other') then
    raise exception 'Unsupported facility type';
  end if;

  insert into public.healthcare_facilities(name,facility_code,facility_type,district,region,dhims2_uid,created_by)
  values (btrim(_name),nullif(btrim(_facility_code),''),_facility_type,
          nullif(btrim(_district),''),nullif(btrim(_region),''),
          nullif(btrim(_dhims2_uid),''),v_user)
  returning * into v_facility;

  begin
    perform public.seed_facility_reports(v_facility.id);
  exception when undefined_function then
    null;
  end;
  return v_facility;
end;
$$;

revoke all on function public.platform_create_facility(text,text,text,text,text,text) from public,anon;
grant execute on function public.platform_create_facility(text,text,text,text,text,text) to authenticated;

create or replace function public.platform_list_facilities()
returns table(id uuid,name text,facility_code text,facility_type text,district text,region text,is_active boolean,created_at timestamptz)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.user_roles ur
    where ur.user_id=(select auth.uid()) and ur.role='system_superuser'::public.app_role
  ) then raise exception 'Only system super administrators may view platform facilities'; end if;
  return query
    select hf.id,hf.name,hf.facility_code,hf.facility_type,hf.district,hf.region,hf.is_active,hf.created_at
    from public.healthcare_facilities hf order by hf.created_at desc;
end;
$$;

revoke all on function public.platform_list_facilities() from public,anon;
grant execute on function public.platform_list_facilities() to authenticated;

notify pgrst,'reload schema';