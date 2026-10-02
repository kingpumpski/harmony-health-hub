import assert from 'node:assert/strict';
import fs from 'node:fs';

const migrationPath = 'supabase/migrations/20261002132500_patient_hub_read_rpc_get_compatibility.sql';
const migration = fs.readFileSync(migrationPath, 'utf8').toLowerCase();
const hub = fs.readFileSync('src/pages/patients/PatientHub.tsx', 'utf8');

for (const signature of [
  'public.get_patient_appointments(uuid, integer)',
  'public.get_patient_admission_history(uuid)',
  'public.get_patient_hub_clinical_snapshot(uuid)',
  'public.get_patient_current_treatment_snapshot(uuid, uuid)',
  'public.get_patient_bmi_context(uuid)',
  'public.get_attending_patient_history(uuid, uuid)',
]) {
  assert.ok(migration.includes(`alter function ${signature} stable`), `Missing STABLE volatility for ${signature}`);
}
assert.ok(migration.includes("notify pgrst, 'reload schema'"));
assert.ok(hub.includes("db.rpc('get_patient_appointments', { _patient_id: patientId, _limit: 100 }, { get: true })"));
assert.ok(hub.includes("db.rpc('get_patient_hub_clinical_snapshot', { _patient_id: patientId }, { get: true })"));
assert.ok(hub.includes("db.rpc('get_patient_admission_history', { _patient_id: patientId }, { get: true })"));
console.log('Patient Hub read RPC GET compatibility contract passed');
