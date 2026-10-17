-- Facility-scoped inbound email storage for Resend email.received events.
create table if not exists public.notification_inbound_emails (
  id uuid primary key default gen_random_uuid(),
  facility_id uuid references public.healthcare_facilities(id) on delete set null,
  provider text not null default 'resend',
  provider_message_id text,
  message_id text,
  from_address text,
  to_addresses text[] not null default '{}',
  cc_addresses text[] not null default '{}',
  subject text,
  text_body text,
  html_body text,
  attachments jsonb not null default '[]'::jsonb,
  received_at timestamptz,
  raw_event jsonb not null default '{}'::jsonb,
  processing_status text not null default 'received',
  created_at timestamptz not null default now()
);

create unique index if not exists notification_inbound_emails_provider_message_uq
  on public.notification_inbound_emails(provider, provider_message_id)
  where provider_message_id is not null;
create index if not exists notification_inbound_emails_facility_created_idx
  on public.notification_inbound_emails(facility_id, created_at desc);

alter table public.notification_inbound_emails enable row level security;
revoke all on public.notification_inbound_emails from anon, authenticated;
