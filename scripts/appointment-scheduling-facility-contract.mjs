import fs from 'node:fs';

const migration = fs.readFileSync('supabase/migrations/20261002050200_appointment_schedulable_patient_directory.sql', 'utf8');
const page = fs.readFileSync('src/pages/Appointments.tsx', 'utf8');

for (const needle of [
  'public.get_appointment_schedulable_patients',
  "p.facility_id IS NOT NULL",
  'p.facility_id = v_facility',
  "REVOKE ALL ON FUNCTION public.get_appointment_schedulable_patients(integer) FROM PUBLIC, anon",
  "GRANT EXECUTE ON FUNCTION public.get_appointment_schedulable_patients(integer) TO authenticated",
  "SET search_path = ''"
]) {
  if (!migration.includes(needle)) throw new Error('Appointment scheduling facility guard missing: ' + needle);
}

for (const needle of [
  "get_appointment_schedulable_patients",
  'Patient facility attribution is unresolved',
  'error.message',
  'No active patients with verified facility attribution are available'
]) {
  if (!page.includes(needle)) throw new Error('Appointment scheduling UX regression: ' + needle);
}

console.log('Appointment scheduling facility attribution contract passed');
