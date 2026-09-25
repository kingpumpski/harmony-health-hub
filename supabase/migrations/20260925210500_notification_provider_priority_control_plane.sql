-- Deterministic provider priority and primary-provider control for facility notification delivery.
-- Lower priority values are attempted first. Only one primary provider is allowed
-- per facility/channel/environment.
alter table public.facility_notification_provider_connections
  add column if not exists priority integer not null default 100;

alter table public.facility_notification_provider_connections
  add column if not exists is_primary boolean not null default false;

create unique index if not exists facility_notification_provider_primary_uq
  on public.facility_notification_provider_connections(facility_id, channel, environment)
  where is_primary = true;

create index if not exists facility_notification_provider_priority_idx
  on public.facility_notification_provider_connections(facility_id, channel, environment, priority, updated_at);

update public.facility_notification_provider_connections
set priority = 100
where priority is null;
