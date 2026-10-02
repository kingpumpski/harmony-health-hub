import fs from 'node:fs';

const migration = fs.readFileSync('supabase/migrations/20261002130000_scope_appointment_workflows_to_active_facility.sql', 'utf8');
const appointments = fs.readFileSync('src/pages/Appointments.tsx', 'utf8');
const claimMigration = fs.readFileSync('supabase/migrations/20261002191500_harden_appointment_claim_test_mode_boundary.sql', 'utf8');

for (const needle of [
  'a.facility_id = v_facility',
  'p.facility_id = v_facility',
  "RAISE EXCEPTION 'Select an active facility to access the appointment worklist'",
  "RAISE EXCEPTION 'Select an active facility to schedule appointments'",
  'patient_facility IS DISTINCT FROM active_facility',
  "REVOKE ALL ON FUNCTION public.get_appointment_worklist(integer) FROM PUBLIC, anon",
  "REVOKE ALL ON FUNCTION public.get_appointment_schedulable_patients(integer) FROM PUBLIC, anon",
  "REVOKE ALL ON FUNCTION public.create_appointment_workflow(uuid,timestamptz,text,text,text,uuid) FROM PUBLIC, anon",
  "REVOKE ALL ON FUNCTION public.create_appointment_workflow(uuid,timestamptz,text,text) FROM PUBLIC, anon",
  "NOTIFY pgrst, 'reload schema'"
]) {
  if (!migration.includes(needle)) throw new Error('Active-facility appointment guard missing: ' + needle);
}
for (const needle of [
  'public.hms_current_user_is_test_user()',
  'public.hms_test_facility_id()',
  'Test mode is active. Test accounts can claim appointments only for patients in the Harmony Health Hub Test Facility',
  'REVOKE ALL ON FUNCTION public.claim_appointment(uuid) FROM PUBLIC, anon',
  'GRANT EXECUTE ON FUNCTION public.claim_appointment(uuid) TO authenticated',
]) {
  if (!claimMigration.includes(needle)) throw new Error('Appointment claim test-mode boundary missing: ' + needle);
}
if (!appointments.includes('facility context mismatch') ||
    !appointments.includes('Switch to the patient')) {
  throw new Error('Appointment UI must explain how to recover from facility context mismatch');
}
const appointmentPage = fs.readFileSync('src/pages/Appointments.tsx', 'utf8');
for (const call of [
  "supabase.rpc('get_appointment_schedulable_patients' as never, { _limit: 300 } as never, { get: true } as never)",
  "supabase.rpc('get_appointment_worklist' as never, { _limit: 300 } as never, { get: true } as never)",
  "supabase.rpc('get_appointment_clinicians' as never, {} as never, { get: true } as never)",
]) {
  if (!appointmentPage.includes(call)) throw new Error('Read-only appointment RPC must use GET: ' + call);
}

console.log('Active-facility appointment workflow contract passed');
