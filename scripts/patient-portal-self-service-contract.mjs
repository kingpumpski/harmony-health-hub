import fs from 'node:fs';

const migration = fs.readdirSync('supabase/migrations').filter(n=>n.endsWith('.sql')).sort().map(n=>fs.readFileSync('supabase/migrations/'+n,'utf8')).join('\n');
const telemedicine = fs.readFileSync('src/pages/Telemedicine.tsx','utf8');
const appointments = fs.readFileSync('src/pages/Appointments.tsx','utf8');
const billing = fs.readFileSync('src/pages/Billing.tsx','utf8');
const records = fs.readFileSync('src/pages/MedicalRecords.tsx','utf8');
const ai = fs.readFileSync('supabase/functions/ai-clinical-assist/index.ts','utf8');
const sidebar = fs.readFileSync('src/components/layout/Sidebar.tsx','utf8');

for (const needle of [
  'create or replace function public.get_patient_portal_identity()',
  'create or replace function public.get_patient_appointments(',
  'create or replace function public.get_patient_invoice_summary(',
  'create or replace function public.get_patient_telemedicine_clinicians()',
  'create or replace function public.request_patient_telemedicine_session(',
  'patient own appointments select',
  'patient own invoices select',
  'patient own video sessions select',
  'create or replace function public.create_patient_appointment(',
  'not current_user_has_role(\'patient\')',
]) if (!migration.toLowerCase().includes(needle.toLowerCase())) throw new Error('Missing patient portal security contract: '+needle);

for (const [name,source,needles] of [
  ['Telemedicine',telemedicine,['PatientTelemedicine','request_patient_telemedicine_session','Request New Telemedicine Session','Select doctor']],
  ['Appointments',appointments,['PatientAppointments','get_patient_appointments','Request Appointment']],
  ['Billing',billing,['PatientBilling','get_patient_invoice_summary','Pay Now']],
  ['MedicalRecords',records,['PatientMedicalRecords','get_patient_hub_clinical_snapshot','Read-only access']],
  ['AI Clinical Assist',ai,["body.mode === 'portal'","hasAnyRole(['patient'])","get_patient_portal_identity"]],
  ['Sidebar',sidebar,["patient: [{ label: 'My Care'",'/patient-portal','/appointments','/telemedicine','/billing']],
]) for (const needle of needles) if (!source.includes(needle)) throw new Error(name+' missing UI contract: '+needle);

if (telemedicine.includes("searchPatientDirectory('', 200)") && !telemedicine.includes("user?.roles?.includes('patient') ? <PatientTelemedicine /> : <StaffTelemedicine />")) throw new Error('Telemedicine must isolate patient and staff flows');
if (ai.includes("body.mode === 'portal'") && !ai.includes("if (!hasAnyRole(['patient']))")) throw new Error('AI portal mode must be patient-role restricted');
console.log('Patient portal self-service contracts passed.');
