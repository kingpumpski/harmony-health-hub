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

create index if not exists idx_staff_signatures_facility_id
  on public.staff_signatures (facility_id);

create index if not exists idx_user_active_facilities_facility_id
  on public.user_active_facilities (facility_id);
