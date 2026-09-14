-- Harden diagnosis import governance before any clinical reference data is loaded.
-- This migration adds a staging table so workbook rows can be validated and approved
-- without writing unreviewed source data directly into stg_diagnoses.

create table if not exists public.diagnosis_import_rows (
  id uuid primary key default gen_random_uuid(),
  batch_id uuid not null references public.diagnosis_import_batches(id) on delete cascade,
  sheet_name text not null,
  source_row_number integer not null check (source_row_number > 0),
  source_code text,
  display_name text,
  description text,
  category text,
  synonyms text[] not null default '{}',
  icd10_code text,
  normalized_key text not null,
  row_status text not null default 'pending'
    check (row_status in ('pending','accepted','rejected','duplicate','unmapped')),
  rejection_reason text,
  icd10_code_id uuid references public.icd_codes(id) on delete restrict,
  created_at timestamptz not null default now()
);

create index if not exists diagnosis_import_rows_batch_idx
  on public.diagnosis_import_rows(batch_id);
create index if not exists diagnosis_import_rows_status_idx
  on public.diagnosis_import_rows(row_status);
create index if not exists diagnosis_import_rows_key_idx
  on public.diagnosis_import_rows(batch_id, normalized_key);

alter table public.diagnosis_import_rows enable row level security;

drop policy if exists diagnosis_import_rows_admin_select on public.diagnosis_import_rows;
create policy diagnosis_import_rows_admin_select
  on public.diagnosis_import_rows for select to authenticated
  using (public.has_role(auth.uid(), 'admin'));

drop policy if exists diagnosis_import_rows_admin_insert on public.diagnosis_import_rows;
create policy diagnosis_import_rows_admin_insert
  on public.diagnosis_import_rows for insert to authenticated
  with check (public.has_role(auth.uid(), 'admin'));

drop policy if exists diagnosis_import_rows_admin_update on public.diagnosis_import_rows;
create policy diagnosis_import_rows_admin_update
  on public.diagnosis_import_rows for update to authenticated
  using (public.has_role(auth.uid(), 'admin'))
  with check (public.has_role(auth.uid(), 'admin'));

notify pgrst, 'reload schema';
