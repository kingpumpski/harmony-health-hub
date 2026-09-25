-- Facility-scoped notification provider credentials.
-- Ciphertext is written by the authenticated provider configuration Edge Function.
-- Plaintext credentials are never stored in application tables.

create table if not exists public.notification_provider_credentials (
  id uuid primary key default gen_random_uuid(),
  facility_id uuid not null references public.healthcare_facilities(id) on delete cascade,
  channel text not null,
  provider text not null,
  environment text not null check (environment in ('sandbox','test','production')),
  credentials_ciphertext text not null,
  secret_version integer not null default 1,
  status text not null default 'configured',
  last_tested_at timestamptz,
  last_error text,
  created_by uuid references auth.users(id),
  updated_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(facility_id, channel, provider, environment)
);

alter table public.notification_provider_credentials enable row level security;
revoke all on public.notification_provider_credentials from anon, authenticated;

comment on table public.notification_provider_credentials is
'Facility-scoped encrypted provider credentials. Ciphertext only; plaintext is handled exclusively by the provider configuration worker.';
