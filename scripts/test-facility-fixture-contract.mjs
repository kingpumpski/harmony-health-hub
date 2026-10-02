import fs from 'node:fs';

const migration = fs.readFileSync('supabase/migrations/20261002114213_seed_synthetic_test_patient_fixture.sql', 'utf8');
for (const needle of [
  'ALTER TABLE public.patients DISABLE TRIGGER patients_assign_active_facility',
  'ALTER TABLE public.patients ENABLE TRIGGER patients_assign_active_facility',
  "'TEST-DEMO-0001'",
  "'Harmony Test'",
  "'Patient'",
  "'Synthetic QA fixture only. Not a real patient; use only in TEST-0001.'",
  "hf.facility_code = 'TEST-0001'",
  'hf.is_active = true',
  'NOT EXISTS (',
  'ON CONFLICT (patient_code) DO NOTHING'
]) {
  if (!migration.includes(needle)) throw new Error('Synthetic test patient fixture migration is missing: ' + needle);
}
if (/UPDATE\s+public\.patients/i.test(migration)) {
  throw new Error('Test fixture migration must never reassign existing patient records.');
}
if (!/^BEGIN;/m.test(migration) || !/^COMMIT;/m.test(migration)) {
  throw new Error('Synthetic test patient fixture must be transaction-wrapped.');
}

const hub = fs.readFileSync('src/pages/patients/PatientHub.tsx', 'utf8');
for (const call of [
  "db.rpc('get_patient_appointments', { _patient_id: patientId, _limit: 100 }, { get: true })",
  "db.rpc('get_patient_hub_clinical_snapshot', { _patient_id: patientId }, { get: true })",
  "db.rpc('get_patient_admission_history', { _patient_id: patientId }, { get: true })"
]) {
  if (!hub.includes(call)) throw new Error('Read-only Patient Hub RPC must use GET: ' + call);
}

console.log('Synthetic test-facility fixture and Patient Hub read-method contract passed');
