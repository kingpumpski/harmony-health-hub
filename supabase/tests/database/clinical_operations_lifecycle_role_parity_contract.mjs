import fs from 'node:fs';
import assert from 'node:assert/strict';

const migration = fs.readFileSync(
  'supabase/migrations/20260928190000_clinical_operations_lifecycle_role_parity.sql',
  'utf8',
);
const page = fs.readFileSync('src/pages/ClinicalOperations.tsx', 'utf8');

const theatreRoles = ["admin", "practitioner", "nurse", "specialist_nurse"];
const transfusionRoles = ["admin", "practitioner", "nurse", "midwife", "specialist_nurse"];

for (const role of theatreRoles) {
  assert.match(migration, new RegExp(`public\\.has_role\\([^)]*,'${role}'\\)`));
}
for (const role of transfusionRoles) {
  assert.match(migration, new RegExp(`public\\.has_role\\([^)]*,'${role}'\\)`));
}

assert.match(page, /specialist_nurse: \['capacity', 'nursing', 'emergency', 'theatre', 'transfusion'\]/);
assert.match(page, /midwife: \['capacity', 'nursing', 'emergency', 'transfusion'\]/);

for (const fn of [
  'create_theatre_case',
  'transition_theatre_case',
  'create_transfusion_record',
  'record_transfusion_event',
]) {
  assert.match(migration, new RegExp(`REVOKE ALL ON FUNCTION public\\.${fn}\\(`));
  assert.match(migration, new RegExp(`GRANT EXECUTE ON FUNCTION public\\.${fn}\\(`));
}

assert.equal(migration.includes("has_role(auth.uid(),'accountant')"), false);
assert.equal(migration.includes("has_role(auth.uid(),'front_desk')"), false);

console.log('Clinical Operations lifecycle role parity contract passed');
