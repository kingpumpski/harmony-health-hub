import fs from 'node:fs';

const source = fs.readFileSync('src/pages/patients/PatientHub.tsx', 'utf8');
const required = [
  "db.rpc('get_patient_current_treatment_snapshot', { _patient_id: patientId, _admission_id: currentAdmissionId }, { get: true })",
  "db.rpc('get_patient_appointments', { _patient_id: patientId, _limit: 100 }, { get: true })",
  "db.rpc('get_patient_hub_clinical_snapshot', { _patient_id: patientId }, { get: true })",
  "db.rpc('get_patient_invoices', { _patient_id: patientId, _limit: 100 })",
  "db.rpc('get_patient_admission_history', { _patient_id: patientId }, { get: true })",
];
for (const call of required) {
  if (!source.includes(call)) throw new Error('Read-only Patient Hub RPC must use GET: ' + call);
}
const migration = fs.readFileSync('supabase/migrations/20261002140000_patient_history_readonly_facility_context.sql', 'utf8');
for (const needle of [
  'public.assert_patient_facility_read_context',
  'pg_catalog.strpos(v_definition',
  'get_patient_appointments(uuid,integer)',
  'get_patient_admission_history(uuid)',
  'get_patient_current_treatment_snapshot(uuid,uuid)',
  'get_patient_hub_clinical_snapshot(uuid)',
  'get_patient_bmi_context(uuid)',
  'get_attending_patient_history(uuid,uuid)',
  'REVOKE ALL ON FUNCTION public.assert_patient_facility_read_context(uuid) FROM PUBLIC, anon, authenticated'
]) {
  if (!migration.includes(needle)) throw new Error('Read-only facility-context contract missing: ' + needle);
}
if (source.includes("db.rpc('get_patient_invoices', { _patient_id: patientId, _limit: 100 }, { get: true })")) {
  throw new Error('Volatile invoice history RPC must remain on POST');
}
console.log('Patient Hub read-only RPC HTTP-method and facility-context contracts passed');
