-- Allow multiple email providers per facility/environment and authorize IT Admin.
drop index if exists public.facility_notification_provider_connections_env_uq;
create unique index if not exists facility_notification_provider_connections_provider_env_uq
  on public.facility_notification_provider_connections(facility_id, channel, provider, environment);

create or replace function public.set_facility_notification_provider(
  _facility_id uuid,_channel text,_provider text,_environment text default 'sandbox',
  _secret_reference text default null,_sender_identity text default null,_account_reference text default null
) returns public.facility_notification_provider_connections
language plpgsql security definer set search_path=public as $function$
declare v public.facility_notification_provider_connections;
begin
  if auth.uid() is null or not (public.has_role(auth.uid(),'admin') or public.has_role(auth.uid(),'it_admin')) then raise exception 'Only administrators or IT administrators may configure notification providers'; end if;
  if not public.has_facility_access(auth.uid(),_facility_id) then raise exception 'Facility access required'; end if;
  insert into public.facility_notification_provider_connections(facility_id,channel,provider,environment,secret_reference,sender_identity,account_reference,status,created_by,updated_by)
  values(_facility_id,_channel,_provider,_environment,nullif(trim(_secret_reference),''),nullif(trim(_sender_identity),''),nullif(trim(_account_reference),''),'configured',auth.uid(),auth.uid())
  on conflict(facility_id,channel,provider,environment) do update set secret_reference=excluded.secret_reference,sender_identity=excluded.sender_identity,account_reference=excluded.account_reference,status='configured',last_error=null,updated_by=auth.uid(),updated_at=now()
  returning * into v;
  return v;
end; $function$;
