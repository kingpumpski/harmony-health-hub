import assert from 'node:assert/strict';
import fs from 'node:fs';

const migration = fs.readFileSync(
  'supabase/migrations/20260923173000_revoked_helper_dependency_reconciliation.sql',
  'utf8',
);

for (const fn of [
  'create_patient_appointment',
  'get_pending_specialist_referrals',
  'patient_coverage_details',
  'attach_lab_catalogue_to_order',
]) {
  assert.match(migration, new RegExp('CREATE OR REPLACE FUNCTION public\\.' + fn));
}

assert.equal(migration.includes('public.is_clinical_staff('), false);
assert.equal(migration.includes('profiles.role'), false);
assert.equal(migration.includes('SELECT role INTO'), false);

assert.match(migration, /public\.has_role\(auth\.uid\(\),'practitioner'/);
assert.match(migration, /public\.has_role\(auth\.uid\(\),'nurse'/);
assert.match(migration, /public\.has_role\(auth\.uid\(\),'midwife'/);
assert.match(migration, /public\.has_role\(auth\.uid\(\),'specialist_nurse'/);
assert.match(migration, /public\.has_role\(auth\.uid\(\),'lab_technician'/);

assert.match(migration, /COALESCE\(status,'active'\) <> 'inactive'/);
assert.match(migration, /REVOKE ALL ON FUNCTION public\.create_patient_appointment/);
assert.match(migration, /REVOKE ALL ON FUNCTION public\.get_pending_specialist_referrals/);
assert.match(migration, /REVOKE ALL ON FUNCTION public\.patient_coverage_details/);
assert.match(migration, /REVOKE ALL ON FUNCTION public\.attach_lab_catalogue_to_order/);

console.log('revoked helper dependency reconciliation contract passed');
