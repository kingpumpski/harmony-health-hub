import fs from 'node:fs';

const read = (path) => fs.readFileSync(path, 'utf8');
const encounters = read('src/pages/Encounters.tsx');
const worklist = read('src/components/workflow/WorklistDataTable.tsx');
const loading = read('src/components/system/RouteLoadingScreen.tsx');
const app = read('src/App.tsx');
const sidebar = read('src/components/layout/Sidebar.tsx');
const header = read('src/components/layout/Header.tsx');
const billing = read('src/pages/Billing.tsx');
const patientHub = read('src/pages/patients/PatientHub.tsx');
const submitMigration = read('supabase/migrations/20260930020000_encounter_draft_edit_workflow.sql');
const lifecycleMigration = read('supabase/migrations/20260914110000_encounter_lifecycle_integrity_hardening.sql');

for (const key of [
  'label: "Encounter ID", required: true',
  'label: "Patient name", required: true',
  'label: "Consultation type", required: true',
  'label: "Clinician name", required: true',
  'label: "Encounter date & time", required: true',
  'label: "Timestamp / last modified", required: true',
  'label: "Status", required: true',
  'setIsNewEncounterOpen(true)',
  'role="dialog" aria-modal="true" aria-labelledby="new-encounter-title"',
  'Principal diagnosis required',
  'setSearchParams({ patient: item.patient_id, encounter: item.id })',
  'Initiate admission',
]) {
  if (!encounters.includes(key)) throw new Error('Encounter UI contract missing: ' + key);
}
if (!worklist.includes('disabled={column.required}')) throw new Error('Required worklist columns can be hidden');
if (!worklist.includes('column.defaultVisible !== false')) throw new Error('Optional column defaults are not respected');
if (!loading.includes('Loading {moduleName}')) throw new Error('Route loading message is not contextual');
if (!app.includes('<Navigate to="/billing" replace />')) throw new Error('Legacy finance route does not redirect to Billing');
if (sidebar.includes("label: 'Finance'") || sidebar.includes("item(CreditCard, 'Finance'")) throw new Error('Legacy Finance sidebar labels remain');
if (!billing.includes("navigate('/insurance-claims')")) throw new Error('Billing does not link to the insurance/NHIS claims worklist');
if (!header.includes('setNotificationAttention(unreadRows.length > 0)')) throw new Error('Notification attention does not track unread acknowledgements');
if (!patientHub.includes("db.rpc('get_patient_appointments', { _patient_id: patientId, _limit: 100 }, { get: true })")) throw new Error('Patient Hub appointment history must use GET for its STABLE RPC');
if (!submitMigration.includes('Completed or cancelled encounters are read-only')) throw new Error('Encounter draft lifecycle guard missing');
if (!lifecycleMigration.includes('Principal diagnosis required before final submission')) throw new Error('Server-side principal diagnosis enforcement missing');

console.log('Encounter, loading, billing navigation, notification acknowledgement, and Patient Hub regression contract passed');
