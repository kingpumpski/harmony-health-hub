import fs from 'node:fs';
import assert from 'node:assert/strict';

const migration = fs.readFileSync(
  'supabase/migrations/20260928143000_harden_visit_coverage_role_boundary.sql',
  'utf8',
);

assert.ok(migration.includes('CREATE OR REPLACE FUNCTION public.activate_patient_visit_coverage'));
assert.equal(migration.includes('is_clinical_staff('), false);
assert.ok(migration.includes("has_role(uid,'accountant')"));
assert.ok(migration.includes("has_role(uid,'front_desk')"));
assert.ok(migration.includes("has_role(uid,'practitioner')"));
assert.ok(migration.includes("has_role(uid,'radiology_technician')"));
assert.ok(migration.includes('REVOKE ALL ON FUNCTION public.activate_patient_visit_coverage'));
assert.ok(migration.includes('GRANT EXECUTE ON FUNCTION public.activate_patient_visit_coverage'));
