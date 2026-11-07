-- Restore reference/internal tables before the following RLS hardening migration.
-- Columns follow the repository's generated Supabase database types.
create table if not exists public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  action text,
  created_at timestamptz default now(),
  new_data jsonb,
  old_data jsonb,
  record_id text,
  table_name text,
  user_id uuid
);

create table if not exists public.sync_queue (
  id uuid primary key default gen_random_uuid(),
  payload jsonb,
  synced boolean default false,
  table_name text
);

create table if not exists public.lab_tests (
  id uuid primary key default gen_random_uuid(),
  loinc_code text,
  normal_range text,
  specimen text,
  test_name text,
  created_at timestamptz default now()
);
