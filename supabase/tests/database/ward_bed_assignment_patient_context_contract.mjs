import assert from 'node:assert/strict';
import fs from 'node:fs';

const migration=fs.readFileSync(
  'supabase/migrations/20260924063000_harden_ward_bed_assignment_patient_context.sql',
  'utf8',
);

assert.match(migration,/Patient not found/i);
assert.match(migration,/Admission not found/i);
assert.match(migration,/admission_patient_id IS DISTINCT FROM _patient_id/i);
assert.match(migration,/Admission does not belong to patient/i);
assert.match(migration,/admission_status IS DISTINCT FROM 'admitted'/i);
assert.match(migration,/REVOKE ALL ON FUNCTION public\.assign_ward_bed\(uuid, uuid, uuid\)/i);
assert.match(migration,/GRANT EXECUTE ON FUNCTION public\.assign_ward_bed\(uuid, uuid, uuid\) TO authenticated/i);

console.log('ward-bed assignment patient context contract passed');
