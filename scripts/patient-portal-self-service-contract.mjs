import fs from 'node:fs';

const migration = fs.readdirSync('supabase/migrations').filter(n=>n.endsWith('.sql')).sort().map(n=>fs.readFileSync('supabase/migrations/'+n,'utf8')).join('\n');
const telemedicine = fs.readFileSync('src/pages/Telemedicine.tsx','utf8');
const appointments = fs.readFileSync('src/pages/Appointments.tsx','utf8');
const billing = fs.readFileSync('src/pages/Billing.tsx','utf8');
const records = fs.readFileSync('src/pages/MedicalRecords.tsx','utf8');
const ai = fs.readFileSync('supabase/functions/ai-clinical-assist/index.ts','utf8');
const sidebar = fs.readFileSync('src/components/layout/Sidebar.tsx','utf8');
const aiReportRuntimeMigration = fs.readFileSync('supabase/migrations/20261007093000_reconcile_ai_report_runtime_search_paths.sql','utf8');
const localDateTime = fs.readFileSync('src/lib/dateTimeLocal.ts','utf8');

if (!localDateTime.includes('getTimezoneOffset()') || !localDateTime.includes("toISOString().slice(0, 16)")) throw new Error('datetime-local formatter must compensate for the browser timezone before serializing');
const patientPortalSource = fs.readFileSync('src/pages/PatientPortal.tsx','utf8');
const identityFailureBranch = patientPortalSource.slice(patientPortalSource.indexOf('if (identityError || !portalPatient)'), patientPortalSource.indexOf('const requests = await Promise.allSettled'));
for (const stateClear of ['setPatient(null)', 'setAppts([])', 'setSessions([])', 'setInvoices([])', 'setReports([])', 'setClinicalSnapshot(null)']) {
  if (!identityFailureBranch.includes(stateClear)) throw new Error('Patient portal must clear stale data when identity verification fails: '+stateClear);
}
for (const [name, source] of [['PatientPortal', fs.readFileSync('src/pages/PatientPortal.tsx','utf8')], ['Telemedicine', telemedicine]]) {
  if (!source.includes("import { toLocalDateTimeInputValue } from '@/lib/dateTimeLocal'")) throw new Error(name+' must use the timezone-safe datetime-local formatter');
  if (source.includes('new Date().toISOString().slice(0,16)') || source.includes('new Date().toISOString().slice(0, 16)')) throw new Error(name+' must not derive datetime-local min values directly from UTC');
}

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
  ['MedicalRecords',records,['PatientMedicalRecords','get_patient_hub_clinical_snapshot','patient-facing longitudinal medical record']],
  ['AI Clinical Assist',ai,["body.mode === 'portal'","hasAnyRole(['patient'])","get_patient_portal_identity"]],
  ['Sidebar',sidebar,["patient: [{ label: 'My Care'",'/patient-portal','/appointments','/telemedicine','/billing']],
]) for (const needle of needles) if (!source.includes(needle)) throw new Error(name+' missing UI contract: '+needle);

const patientTelemedicine = telemedicine.slice(telemedicine.indexOf('function PatientTelemedicine()'));
if (!patientTelemedicine.includes("supabase.rpc('get_patient_portal_video_sessions', { _limit: 50 })")) {
  throw new Error('Patient telemedicine must load sessions through the ownership-checked portal RPC');
}
if (patientTelemedicine.includes("supabase.from('video_sessions')")) {
  throw new Error('Patient telemedicine must not bypass the patient-scoped session RPC with a direct table read');
}
const patientLoadBlock = patientTelemedicine.slice(
  patientTelemedicine.indexOf('const load = async (at = scheduledAt)'),
  patientTelemedicine.indexOf('useEffect(() => { void load(scheduledAt); }, []);')
);
if (!patientLoadBlock.includes('if (sessionError)') || !patientLoadBlock.includes('if (clinicianError)')) {
  throw new Error('Patient telemedicine must handle session and clinician availability errors independently');
}
if (patientLoadBlock.includes('if (sessionError || clinicianError)')) {
  throw new Error('Clinician lookup failure must not hide the patient telemedicine session history');
}
if (!patientLoadBlock.includes('setSessions(rows ?? [])')) {
  throw new Error('Patient telemedicine session history must load independently of clinician availability');
}

if (telemedicine.includes("searchPatientDirectory('', 200)") && !telemedicine.includes("user?.roles?.includes('patient') ? <PatientTelemedicine /> : <StaffTelemedicine />")) throw new Error('Telemedicine must isolate patient and staff flows');
if (ai.includes("body.mode === 'portal'") && !ai.includes("if (!hasAnyRole(['patient']))")) throw new Error('AI portal mode must be patient-role restricted');
if (!aiReportRuntimeMigration.toLowerCase().includes('alter function public.get_ai_report_requests(uuid, integer)\n  set search_path = pg_catalog, public') || !aiReportRuntimeMigration.toLowerCase().includes('alter function public.create_ai_report_request(uuid, text)\n  set search_path = pg_catalog, public') || !aiReportRuntimeMigration.toLowerCase().includes('alter function public.complete_ai_report_request(uuid, text, text)\n  set search_path = pg_catalog, public') || !aiReportRuntimeMigration.toLowerCase().includes('alter function public.create_patient_appointment(uuid, timestamptz, text, text)\n  set search_path = pg_catalog, public')) throw new Error('AI report and appointment SECURITY DEFINER runtime search paths must resolve public.has_role safely');

for (const needle of [
  "const [unavailableSections, setUnavailableSections] = useState<string[]>([]);",
  "setUnavailableSections(labels.filter((_, index) => failedSections.includes(index)))",
  "Appointments are temporarily unavailable. Please refresh to try again.",
  "Telemedicine sessions are temporarily unavailable. Please refresh to try again.",
  "Invoices are temporarily unavailable. Please refresh to try again.",
  "Reports are temporarily unavailable. Please refresh to try again.",
  "Medical records are temporarily unavailable. Please refresh to try again.",
]) {
  if (!patientPortalSource.includes(needle)) throw new Error("Patient portal must distinguish unavailable data from empty results: " + needle);
}

console.log('Patient portal self-service contracts passed.');
