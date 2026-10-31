import fs from 'node:fs';

const migration = fs.readFileSync('supabase/migrations/20260929163000_cover_unindexed_foreign_keys.sql', 'utf8');

const required = [
  'idx_clinical_reference_values_created_by',
  'idx_clinical_reference_values_updated_by',
  'idx_inpatient_bed_movements_moved_by',
  'idx_inpatient_bed_movements_source_bed_id',
  'idx_insurance_companies_created_by',
  'idx_notification_provider_credentials_created_by',
  'idx_notification_provider_credentials_updated_by',
  'idx_nursing_notes_admission_id',
  'idx_nursing_notes_author_id',
  'idx_nursing_notes_patient_id',
  'idx_patient_account_credits_invoice_id',
  'idx_patient_account_credits_payment_id',
  'idx_user_active_facilities_facility_id',
];

const activeFacilityTableStart = migration.indexOf('create table if not exists public.user_active_facilities');
const activeFacilityIndex = migration.indexOf('idx_user_active_facilities_facility_id');
if (activeFacilityTableStart < 0 || activeFacilityIndex < activeFacilityTableStart) {
  console.error('Unindexed FK contract failed: active facility context table must exist before its FK index.');
  process.exitCode = 1;
}
if (!migration.includes('user_active_facilities_select_own') || !migration.includes('using (user_id = (select auth.uid()))')) {
  console.error('Unindexed FK contract failed: active facility context must retain caller-scoped SELECT RLS.');
  process.exitCode = 1;
}

const missing = required.filter((name) => !migration.includes(name));
if (missing.length) {
  console.error('Unindexed FK contract failed:', missing);
  process.exitCode = 1;
} else {
  console.log('Unindexed FK contract passed.');
}
