-- Cover foreign-key columns identified by the Supabase performance advisor.
-- These indexes support FK enforcement and common relationship lookups without
-- removing any existing clinical/financial indexes.

create index if not exists idx_clinical_reference_values_created_by
  on public.clinical_reference_values (created_by);

create index if not exists idx_clinical_reference_values_updated_by
  on public.clinical_reference_values (updated_by);

create index if not exists idx_inpatient_bed_movements_moved_by
  on public.inpatient_bed_movements (moved_by);

create index if not exists idx_inpatient_bed_movements_source_bed_id
  on public.inpatient_bed_movements (source_bed_id);

create index if not exists idx_insurance_companies_created_by
  on public.insurance_companies (created_by);

create index if not exists idx_notification_provider_credentials_created_by
  on public.notification_provider_credentials (created_by);

create index if not exists idx_notification_provider_credentials_updated_by
  on public.notification_provider_credentials (updated_by);

create index if not exists idx_nursing_notes_admission_id
  on public.nursing_notes (admission_id);

create index if not exists idx_nursing_notes_author_id
  on public.nursing_notes (author_id);

create index if not exists idx_nursing_notes_patient_id
  on public.nursing_notes (patient_id);

create index if not exists idx_patient_account_credits_invoice_id
  on public.patient_account_credits (invoice_id);

create index if not exists idx_patient_account_credits_payment_id
  on public.patient_account_credits (payment_id);

-- Staff signatures are stored in public.user_document_signatures,
-- which is keyed by user_id and has no facility_id foreign key.
-- Do not create a facility_id index for a non-existent legacy table.

-- Active facility context is referenced by the facility governance and
-- membership workflows. No earlier migration creates this relation, so define
-- its minimal canonical shape before adding its FK index or dependent routines.
create table if not exists public.user_active_facilities (
  user_id uuid primary key references auth.users(id) on delete cascade,
  facility_id uuid not null references public.healthcare_facilities(id) on delete restrict,
  updated_at timestamptz not null default now()
);

alter table public.user_active_facilities enable row level security;
revoke all on table public.user_active_facilities from public, anon, authenticated;

drop policy if exists user_active_facilities_select_own
  on public.user_active_facilities;
create policy user_active_facilities_select_own
  on public.user_active_facilities
  for select
  to authenticated
  using (user_id = (select auth.uid()));

create index if not exists idx_user_active_facilities_facility_id
  on public.user_active_facilities (facility_id);
