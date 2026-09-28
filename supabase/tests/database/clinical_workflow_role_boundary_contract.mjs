import fs from 'node:fs';
import assert from 'node:assert/strict';

const migration = fs.readFileSync(
  'supabase/migrations/20260928141500_harden_clinical_workflow_role_boundaries.sql',
  'utf8',
);

for (const fn of [
  'complete_service_order',
  'mark_service_order_in_progress',
  'create_treatment_template_workflow',
]) {
  assert.ok(migration.includes('CREATE OR REPLACE FUNCTION public.' + fn));
  assert.ok(migration.includes('REVOKE ALL ON FUNCTION public.' + fn));
}

assert.equal(migration.includes('is_clinical_staff('), false);

for (const role of [
  'admin',
  'practitioner',
  'nurse',
  'midwife',
  'specialist_nurse',
  'pharmacist',
]) {
  assert.ok(migration.includes("has_role(auth.uid(),'" + role + "'"));
  assert.ok(migration.includes("has_role(uid,'" + role + "'") || role === 'admin' || role === 'practitioner' || role === 'nurse' || role === 'midwife' || role === 'specialist_nurse' || role === 'pharmacist');
}
