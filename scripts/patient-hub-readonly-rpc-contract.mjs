import fs from 'node:fs';

const source = fs.readFileSync('src/pages/patients/PatientHub.tsx', 'utf8');
const required = [
  "db.rpc('get_patient_current_treatment_snapshot', { _patient_id: patientId, _admission_id: currentAdmissionId })",
  "db.rpc('get_patient_appointments', { _patient_id: patientId, _limit: 100 })",
  "db.rpc('get_patient_hub_clinical_snapshot', { _patient_id: patientId })",
  "db.rpc('get_patient_admission_history', { _patient_id: patientId })",
];
for (const call of required) {
  if (!source.includes(call)) throw new Error('Read-only Patient Hub RPC must use standard POST transport: ' + call);
}
const migration = fs.readFileSync('supabase/migrations/20261002053306_patient_history_readonly_facility_context.sql', 'utf8');
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

const testBoundary = fs.readFileSync('supabase/migrations/20261002111152_enforce_test_user_patient_read_facility_boundary.sql', 'utf8');
const testGuard = testBoundary.indexOf('IF public.hms_current_user_is_test_user() THEN');
const adminBypass = testBoundary.indexOf("public.has_role(uid, 'admin'::public.app_role)");
if (testGuard < 0 || adminBypass < 0 || testGuard > adminBypass) {
  throw new Error('Patient history reads must enforce test-user facility isolation before administrator cross-facility access');
}
for (const needle of [
  'public.hms_test_facility_id()',
  'patient_facility IS DISTINCT FROM test_facility',
  'TEST-0001',
  'REVOKE ALL ON FUNCTION public.assert_patient_facility_read_context(uuid) FROM PUBLIC, anon, authenticated'
]) {
  if (!testBoundary.includes(needle)) throw new Error('Patient history test-facility boundary missing: ' + needle);
}

console.log('Patient Hub read-only RPC HTTP-method and facility-context contracts passed');
