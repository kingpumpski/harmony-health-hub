-- Diagnosis workbook import governance and audit batch tracking.
-- This migration mirrors the production schema already applied to the canonical project.

create table if not exists public.diagnosis_import_batches (
  id uuid primary key default gen_random_uuid(),
  standard_id uuid references public.diagnosis_standards(id) on delete restrict,
  file_name text,
  source_format text not null default 'xlsx',
  source_version text,
  assessment_only boolean not null default true,
  status text not null default 'assessed'
    check (status in ('assessed','validated','approved','importing','completed','completed_with_errors','failed','cancelled')),
  total_sheets integer not null default 0,
  total_rows integer not null default 0,
  accepted_rows integer not null default 0,
  rejected_rows integer not null default 0,
  duplicate_rows integer not null default 0,
  unmapped_rows integer not null default 0,
  validation_errors jsonb not null default '[]'::jsonb,
  sheet_assessments jsonb not null default '[]'::jsonb,
  created_by uuid references auth.users(id) on delete set null,
  approved_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  approved_at timestamptz,
  completed_at timestamptz
);

create index if not exists diagnosis_import_batches_status_idx
  on public.diagnosis_import_batches(status);
create index if not exists diagnosis_import_batches_standard_id_idx
  on public.diagnosis_import_batches(standard_id);
create index if not exists diagnosis_import_batches_created_at_idx
  on public.diagnosis_import_batches(created_at desc);

alter table public.diagnosis_import_batches enable row level security;

drop policy if exists diagnosis_import_batches_admin_select on public.diagnosis_import_batches;
create policy diagnosis_import_batches_admin_select
  on public.diagnosis_import_batches
  for select
  to authenticated
  using (public.has_role(auth.uid(), 'admin'));

drop policy if exists diagnosis_import_batches_admin_insert on public.diagnosis_import_batches;
create policy diagnosis_import_batches_admin_insert
  on public.diagnosis_import_batches
  for insert
  to authenticated
  with check (public.has_role(auth.uid(), 'admin'));

drop policy if exists diagnosis_import_batches_admin_update on public.diagnosis_import_batches;
create policy diagnosis_import_batches_admin_update
  on public.diagnosis_import_batches
  for update
  to authenticated
  using (public.has_role(auth.uid(), 'admin'))
  with check (public.has_role(auth.uid(), 'admin'));

notify pgrst, 'reload schema';
