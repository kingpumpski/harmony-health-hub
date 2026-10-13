import assert from 'node:assert/strict';
import fs from 'node:fs';

const migrationPath = 'supabase/migrations/20261013100000_harden_atomic_inpatient_bed_transfer_facility_boundary.sql';
const migration = fs.readFileSync(migrationPath, 'utf8');
const wardBoard = fs.readFileSync('src/pages/WardBedBoard.tsx', 'utf8');

assert.match(migration, /CREATE OR REPLACE FUNCTION public\.transfer_inpatient_bed\s*\(\s*_admission_id uuid,\s*_target_bed_id uuid,\s*_summary text DEFAULT NULL/s);
assert.match(migration, /RETURNS jsonb[\s\S]*?SECURITY DEFINER[\s\S]*?SET search_path = ''/);
assert.match(migration, /Authentication required/);
assert.match(migration, /Inpatient transfer is not permitted/);
assert.match(migration, /public\.current_user_facility_id\(\)/);
assert.match(migration, /public\.has_role\(v_uid, 'admin'::public\.app_role\)/);
assert.match(migration, /public\.has_role\(v_uid, 'practitioner'::public\.app_role\)/);
assert.match(migration, /public\.has_role\(v_uid, 'nurse'::public\.app_role\)/);
assert.match(migration, /public\.has_role\(v_uid, 'specialist_nurse'::public\.app_role\)/);
assert.match(migration, /public\.has_role\(v_uid, 'midwife'::public\.app_role\)/);

// Guard the schema dependencies used by the migration so renamed tables/columns
// or removed audit hooks are caught by CI before deployment.
for (const dependency of [
  /v_admission public\.admissions%ROWTYPE/,
  /v_target public\.ward_beds%ROWTYPE/,
  /v_source public\.ward_beds%ROWTYPE/,
  /v_target_ward public\.ward_units%ROWTYPE/,
  /v_source_ward public\.ward_units%ROWTYPE/,
  /SELECT p\.facility_id INTO v_patient_facility[\s\S]*?FROM public\.patients p/,
  /v_admission\.facility_id/,
  /v_admission\.patient_id/,
  /v_target\.ward_id/,
  /v_target\.bed_number/,
  /ORDER BY occupied_at DESC NULLS LAST/,
  /SET patient_id = NULL,[\s\S]*?admission_id = NULL,[\s\S]*?status = 'cleaning'/,
  /INSERT INTO public\.care_transitions\s*\([\s\S]*?facility_id/s,
  /public\.record_system_audit\s*\([\s\S]*?'inpatient_bed_transferred'/s,
]) {
  assert.match(migration, dependency, `Missing inpatient transfer dependency contract: ${dependency}`);
}

assert.match(migration, /v_admission\.facility_id IS DISTINCT FROM v_facility/);
assert.match(migration, /v_patient_facility IS DISTINCT FROM v_facility/);
assert.match(migration, /v_target_ward\.facility_id IS DISTINCT FROM v_facility/);
assert.match(migration, /v_source_ward\.facility_id IS DISTINCT FROM v_facility/);
assert.match(migration, /pg_advisory_xact_lock/);
assert.match(migration, /FOR UPDATE/);
assert.match(migration, /INSERT INTO public\.care_transitions/);
assert.match(migration, /PERFORM public\.record_system_audit/);
assert.match(migration, /REVOKE ALL ON FUNCTION public\.transfer_inpatient_bed\(uuid, uuid, text\) FROM PUBLIC, anon/);
assert.match(migration, /GRANT EXECUTE ON FUNCTION public\.transfer_inpatient_bed\(uuid, uuid, text\) TO authenticated/);
assert.match(wardBoard, /supabase\.rpc\('transfer_inpatient_bed'/);

console.log('Inpatient bed-transfer facility boundary contract passed.');
