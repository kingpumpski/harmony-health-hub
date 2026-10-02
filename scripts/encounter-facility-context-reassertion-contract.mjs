import assert from 'node:assert/strict';
import fs from 'node:fs';

const migrationPath = 'supabase/migrations/20261002180000_reassert_start_appointment_encounter_facility_context.sql';
const migration = fs.readFileSync(migrationPath, 'utf8');

for (const needle of [
  'public.current_user_facility_id()',
  'public.hms_current_user_is_test_user()',
  'public.hms_test_facility_id()',
  'IF v_facility IS NULL THEN',
  'IF v_patient_facility IS DISTINCT FROM v_facility THEN',
  'Select the patient facility before starting the encounter',
  "NOTIFY pgrst, 'reload schema'",
  'REVOKE ALL ON FUNCTION public.start_appointment_encounter(uuid,text,text) FROM PUBLIC, anon',
  'GRANT EXECUTE ON FUNCTION public.start_appointment_encounter(uuid,text,text) TO authenticated'
]) {
  assert.ok(migration.includes(needle), 'Encounter facility-context migration missing: ' + needle);
}

assert.ok(
  migration.indexOf('IF v_patient_facility IS DISTINCT FROM v_facility THEN') <
    migration.indexOf('UPDATE public.appointments\n  SET attending_officer_id'),
  'Facility context must be validated before changing appointment status'
);
assert.ok(!migration.includes("set_config('hms.facility_reconciliation','on'"), 'Encounter start must not bypass facility reconciliation controls');

console.log('Encounter-start facility-context reassertion contract passed');
