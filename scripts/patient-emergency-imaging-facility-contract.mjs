import assert from 'node:assert/strict';
import fs from 'node:fs';

const migration = fs.readFileSync(
  'supabase/migrations/20261003120000_harden_patient_emergency_imaging_facility_context.sql',
  'utf8',
).toLowerCase();

for (const name of [
  'update_patient_workflow',
  'transition_emergency_case',
  'start_imaging_order',
]) {
  assert(migration.includes(`function public.${name}`), `missing definition: ${name}`);
}
assert(migration.includes('assert_patient_facility_context'), 'patient/test-mode context guard missing');
assert(migration.includes('emergency case facility does not match patient facility'), 'emergency facility lineage guard missing');
assert(migration.includes('imaging order facility does not match patient facility'), 'imaging facility lineage guard missing');
assert(migration.includes('s.facility_id is distinct from o.facility_id'), 'linked service-order facility guard missing');
assert(migration.includes('from public,anon'), 'anonymous/public execute revocation missing');
assert(migration.includes('to authenticated'), 'authenticated execute grant missing');
console.log('Patient/emergency/imaging facility contract passed.');
