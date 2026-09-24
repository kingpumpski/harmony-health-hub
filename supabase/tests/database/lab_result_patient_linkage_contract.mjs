import assert from 'node:assert/strict';
import fs from 'node:fs';

const migration=fs.readFileSync(
  'supabase/migrations/20260924060000_harden_lab_result_patient_linkage.sql',
  'utf8',
);

assert.match(migration,/r\.patient_id IS DISTINCT FROM o\.patient_id/i);
assert.match(migration,/Laboratory result and order patient context do not match/i);
assert.match(migration,/o\.encounter_id IS NOT NULL/i);
assert.match(migration,/encounter_patient_id IS DISTINCT FROM o\.patient_id/i);
assert.match(migration,/Laboratory order encounter does not belong to patient/i);
assert.match(migration,/REVOKE ALL ON FUNCTION public\.approve_lab_result\(uuid\)/i);
assert.match(migration,/GRANT EXECUTE ON FUNCTION public\.approve_lab_result\(uuid\) TO authenticated/i);

console.log('lab-result patient linkage contract passed');
