import fs from 'node:fs';
import assert from 'node:assert/strict';

const migration = fs.readFileSync('supabase/migrations/20261002160000_patient_hub_and_test_facility_context_repair.sql', 'utf8');
const appointments = fs.readFileSync('src/pages/Appointments.tsx', 'utf8');
const patientHub = fs.readFileSync('src/pages/patients/PatientHub.tsx', 'utf8');
const vite = fs.readFileSync('vite.config.ts', 'utf8');
const serviceWorker = fs.readFileSync('public/sw.js', 'utf8');

for (const needle of [
  'public.hms_current_user_is_test_user()',
  'public.hms_test_facility_id()',
  'Test mode is active. Test accounts can start encounters only for patients in the Harmony Health Hub Test Facility',
  'v_patient_facility IS DISTINCT FROM v_facility',
  "REVOKE ALL ON FUNCTION public.start_appointment_encounter(uuid,text,text) FROM PUBLIC, anon",
  'public.assert_patient_facility_read_context(_patient_id)',
  "REVOKE ALL ON FUNCTION public.get_patient_profile_for_user(uuid) FROM PUBLIC, anon",
  "GRANT EXECUTE ON FUNCTION public.get_patient_profile_for_user(uuid) TO authenticated",
  "NOTIFY pgrst, 'reload schema'"
]) {
  assert.ok(migration.includes(needle), 'Migration missing facility/security guard: ' + needle);
}

assert.ok(appointments.includes('Test mode is active for this account.'));
assert.ok(appointments.includes('description: workflowErrorMessage(error)'));
assert.ok(patientHub.includes('No patient profile was returned for this record.'));
assert.ok(!patientHub.includes('searchPatients(patientId)'), 'Do not try searching a UUID as a patient name/code after profile lookup fails.');
for (const call of [
  "db.rpc('get_patient_appointments', { _patient_id: patientId, _limit: 100 })",
  "db.rpc('get_patient_hub_clinical_snapshot', { _patient_id: patientId })",
  "db.rpc('get_patient_admission_history', { _patient_id: patientId })"
]) assert.ok(patientHub.includes(call), 'Read-only Patient Hub RPC must use standard POST transport: ' + call);

assert.ok(vite.includes('__hms_spa_redirect'), 'GitHub Pages fallback must preserve and restore deep links.');
assert.ok(vite.includes('writeFileSync("dist/404.html", fallbackHtml)'), 'Production build must emit a redirecting 404 fallback.');
assert.ok(serviceWorker.includes('harmony-health-hub-shell-v15'), 'Service worker cache must be versioned to refresh old clients.');
assert.ok(serviceWorker.includes('if (response.status === 404)'), 'Service worker must fall back to index.html for deep-link navigation.');

console.log('Patient Hub, test-facility encounter and GitHub Pages deep-link contracts passed');
