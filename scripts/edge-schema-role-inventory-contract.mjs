import fs from 'node:fs';
import path from 'node:path';

const root = process.cwd();
const functionsDir = path.join(root, 'supabase', 'functions');
const migrationsDir = path.join(root, 'supabase', 'migrations');
const app = fs.readFileSync(path.join(root, 'src', 'App.tsx'), 'utf8');
const sidebar = fs.readFileSync(path.join(root, 'src', 'components', 'layout', 'Sidebar.tsx'), 'utf8');

const expectedEdgeFunctions = [
  'admin-bulk-import','admin-create-user','ai-clinical-assist','analyze-lab-document',
  'notification-provider-config','notification-scheduler','notification-webhook','notifications-send',
  'notify-lab-result','notify-payment','notify-queue-drain','operational-workspace',
];

const expectedRoles = [
  'admin','it_admin','system_superuser','practitioner','nurse','specialist_nurse','midwife',
  'front_desk','pharmacist','lab_technician','accountant','radiologist','radiology_technician',
  'canteen','patient',
];

const requiredSchemaEntrypoints = [
  'get_patient_directory','get_patient_portal_identity','get_patient_appointments','get_patient_invoice_summary',
  'get_patient_telemedicine_clinicians','request_patient_telemedicine_session','create_patient_appointment',
  'create_ai_report_request','get_ai_report_requests','get_admission_workspace','get_operational_workspace',
  'start_appointment_encounter','update_encounter_draft_workflow','submit_encounter_workflow','add_encounter_diagnosis',
  'create_lab_order_with_payment_gate','collect_lab_sample','enter_lab_result','approve_lab_result',
  'start_imaging_order','complete_imaging_order','get_pharmacy_workspace','create_pharmacy_inventory_item',
  'update_pharmacy_inventory_item','create_service_order','create_invoice','record_invoice_payment',
  'create_meal_plan_workflow','mark_meal_order_delivered',
];

function assert(condition, message) { if (!condition) throw new Error(message); }

const actualEdgeFunctions = fs.readdirSync(functionsDir, { withFileTypes: true })
  .filter((entry) => entry.isDirectory() && fs.existsSync(path.join(functionsDir, entry.name, 'index.ts')))
  .map((entry) => entry.name).filter((name) => name !== '_shared').sort();

assert(JSON.stringify(actualEdgeFunctions) === JSON.stringify([...expectedEdgeFunctions].sort()),
  `Edge Function inventory drift: expected ${expectedEdgeFunctions.join(', ')}, found ${actualEdgeFunctions.join(', ')}`);

for (const slug of expectedEdgeFunctions) {
  const source = fs.readFileSync(path.join(functionsDir, slug, 'index.ts'), 'utf8');
  assert(source.includes('Deno.serve'), `Edge Function ${slug} is missing Deno.serve`);
  if (!['notification-webhook','notify-payment','notify-queue-drain','notification-scheduler'].includes(slug)) {
    assert(source.includes('Authorization') || source.includes('auth.getUser'), `Edge Function ${slug} has no visible authentication boundary`);
  }
}

for (const role of expectedRoles) {
  assert(app.includes(`'${role}'`) || sidebar.includes(`  ${role}:`), `Role ${role} is missing from application role wiring`);
}

const migrationFiles = fs.readdirSync(migrationsDir).filter((name) => name.endsWith('.sql'));
const migrationText = migrationFiles.map((name) => fs.readFileSync(path.join(migrationsDir, name), 'utf8')).join('\n').toLowerCase();
for (const name of requiredSchemaEntrypoints) {
  const pattern = new RegExp(`function\\s+public\\.${name.toLowerCase()}\\s*\\(`);
  assert(pattern.test(migrationText), `Required schema entrypoint ${name} is not represented in repository migrations`);
}

const hardeningMigration = fs.readFileSync(
  path.join(migrationsDir, '20261005153000_reconcile_authenticated_entrypoints_and_edge_schema_inventory.sql'),
  'utf8',
).toLowerCase();
for (const token of ['create_patient_admission','hms_test_facility_id','hms_test_mode_enabled','search_clinical_diagnoses','get_patient_triage_history']) {
  assert(hardeningMigration.includes(token), 'Hardening migration is missing ' + token);
}

assert(!sidebar.includes('Clinical Operation'), 'Legacy Clinical Operation label remains in Sidebar');
assert(!app.includes('Clinical Operation'), 'Legacy Clinical Operation label remains in App');

console.log(`Edge/schema/role inventory contract passed: ${expectedEdgeFunctions.length} Edge Functions, ${expectedRoles.length} roles, ${requiredSchemaEntrypoints.length} core schema entrypoints.`);
