import fs from 'node:fs';
import assert from 'node:assert/strict';

const migration = fs.readFileSync(
  'supabase/migrations/20260928160000_harden_patient_appointment_role_boundary.sql',
  'utf8',
);

assert.match(migration, /CREATE OR REPLACE FUNCTION public\\.create_patient_appointment/);
assert.match(migration, /IF uid IS NULL THEN/);
for (const role of ['admin', 'front_desk', 'practitioner', 'nurse', 'midwife']) {
  assert.match(migration, new RegExp(`public\\\\.has_role\\(uid,'${role}'\\)`));
}
assert.equal(migration.includes('is_clinical_staff('), false);
assert.match(migration, /public\\.create_appointment_workflow\\(/);
assert.match(migration, /REVOKE ALL ON FUNCTION public\\.create_patient_appointment/);
assert.match(migration, /GRANT EXECUTE ON FUNCTION public\\.create_patient_appointment.*authenticated/);
