-- Final facility-boundary hardening for module/service configuration.
create or replace function public.set_hms_facility_module_service(
  _facility_id uuid,_module_id text,_service_available boolean,_readiness_status text default null,_service_notes text default null
)
returns public.hms_facility_modules
language plpgsql security definer set search_path=public as $$
declare r public.hms_facility_modules; v_status text; v_allowed boolean;
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
  v_allowed := public.has_role(auth.uid(),'admin'::public.app_role)
    or public.has_role(auth.uid(),'it_admin'::public.app_role)
    or public.has_role(auth.uid(),'system_superuser'::public.app_role);
  if not v_allowed then raise exception 'Administrator authorization required' using errcode='42501'; end if;
  if not public.has_role(auth.uid(),'system_superuser'::public.app_role)
     and not public.has_facility_access(auth.uid(),_facility_id) then
    raise exception 'Facility access denied' using errcode='42501';
  end if;
  if not exists(select 1 from public.hms_module_catalog where module_id=_module_id) then raise exception 'Unknown HMS module'; end if;
  v_status:=coalesce(_readiness_status,case when _service_available then 'ready' else 'not_available' end);
  if _service_available and v_status<>'ready' then raise exception 'Available services must have readiness_status=ready'; end if;
  insert into public.hms_facility_modules(facility_id,module_id,enabled,service_available,readiness_status,service_notes,verified_by,verified_at,configured_by)
  values(_facility_id,_module_id,_service_available,_service_available,v_status,_service_notes,auth.uid(),case when _service_available then now() end,auth.uid())
  on conflict(facility_id,module_id) do update set
    service_available=excluded.service_available,readiness_status=excluded.readiness_status,service_notes=excluded.service_notes,
    verified_by=auth.uid(),verified_at=case when excluded.service_available then now() else null end,
    enabled=case when excluded.service_available then public.hms_facility_modules.enabled else false end,
    configured_by=auth.uid(),configured_at=now(),effective_from=now(),effective_to=null
  returning * into r;
  return r;
end;
$$;
revoke all on function public.set_hms_facility_module_service(uuid,text,boolean,text,text) from public,anon;
grant execute on function public.set_hms_facility_module_service(uuid,text,boolean,text,text) to authenticated;

create or replace function public.set_hms_facility_module(_facility_id uuid,_module_id text,_enabled boolean)
returns public.hms_facility_modules
language plpgsql security definer set search_path=public as $$
declare r public.hms_facility_modules; v_available boolean; v_allowed boolean;
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
  v_allowed := public.has_role(auth.uid(),'admin'::public.app_role)
    or public.has_role(auth.uid(),'it_admin'::public.app_role)
    or public.has_role(auth.uid(),'system_superuser'::public.app_role);
  if not v_allowed then raise exception 'Administrator authorization required' using errcode='42501'; end if;
  if not public.has_role(auth.uid(),'system_superuser'::public.app_role)
     and not public.has_facility_access(auth.uid(),_facility_id) then
    raise exception 'Facility access denied' using errcode='42501';
  end if;
  if not exists(select 1 from public.hms_module_catalog where module_id=_module_id) then raise exception 'Unknown HMS module'; end if;
  select coalesce(service_available,false) into v_available from public.hms_facility_modules where facility_id=_facility_id and module_id=_module_id;
  if _enabled and not coalesce(v_available,(select not optional from public.hms_module_catalog where module_id=_module_id)) then
    raise exception 'Cannot enable HMS module % until the facility declares the service available',_module_id;
  end if;
  insert into public.hms_facility_modules(facility_id,module_id,enabled,service_available,readiness_status,configured_by)
  values(_facility_id,_module_id,_enabled,coalesce(v_available,_enabled),case when coalesce(v_available,_enabled) then 'ready' else 'not_available' end,auth.uid())
  on conflict(facility_id,module_id) do update set enabled=excluded.enabled,configured_by=auth.uid(),configured_at=now(),effective_from=now(),effective_to=null
  returning * into r;
  return r;
end;
$$;
revoke all on function public.set_hms_facility_module(uuid,text,boolean) from public,anon;
grant execute on function public.set_hms_facility_module(uuid,text,boolean) to authenticated;

drop policy if exists hms_facility_modules_admin_read on public.hms_facility_modules;
create policy hms_facility_modules_admin_read on public.hms_facility_modules
for select to authenticated
using (
  (public.has_role((select auth.uid()),'admin'::public.app_role)
   or public.has_role((select auth.uid()),'it_admin'::public.app_role)
   or public.has_role((select auth.uid()),'system_superuser'::public.app_role))
  and (
    public.has_role((select auth.uid()),'system_superuser'::public.app_role)
    or public.has_facility_access((select auth.uid()),facility_id)
  )
);

comment on function public.set_hms_facility_module_service(uuid,text,boolean,text,text)
is 'Facility-bound service availability declaration. Admin/IT Admin/System Superuser only; non-superusers are restricted to facilities they can access.';
