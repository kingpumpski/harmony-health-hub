import fs from 'node:fs';

const migration = fs.readFileSync('supabase/migrations/20261002170000_enforce_test_user_facility_context.sql', 'utf8');
const appointments = fs.readFileSync('src/pages/Appointments.tsx', 'utf8');
const patientHub = fs.readFileSync('src/pages/patients/PatientHub.tsx', 'utf8');

for (const needle of [
  'FROM public.hms_test_runtime r',
  'WHERE r.id = true AND r.enabled = true',
  'FROM public.hms_test_users tu',
  'tu.user_id = (SELECT auth.uid())',
  'THEN public.hms_test_facility_id()',
  'Test mode restricts this account to the Harmony Health Hub Test Facility (TEST-0001)',
  'WHERE hf.id = v_test_facility AND hf.is_active = true',
  'REVOKE ALL ON FUNCTION public.hms_current_user_is_test_user() FROM PUBLIC, anon, authenticated',
  'REVOKE ALL ON FUNCTION public.current_user_facility_id() FROM PUBLIC, anon, authenticated',
  "NOTIFY pgrst, 'reload schema'"
]) {
  if (!migration.includes(needle)) throw new Error('Test-mode facility isolation guard missing: ' + needle);
}

if (!appointments.includes('Test mode is active') ||
    !appointments.includes('Facility context mismatch')) {
  throw new Error('Appointment workflow must explain test-mode and facility-context failures');
}
if (!patientHub.includes('If the record has no verified facility attribution, an administrator must reconcile it before it can be opened.')) {
  throw new Error('Patient Hub must explain how unresolved historical records are recovered');
}

console.log('Test-mode facility isolation regression contract passed');
