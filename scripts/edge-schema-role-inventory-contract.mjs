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
  'acknowledge_nursing_handover',
  'acknowledge_vital_alert',
  'activate_patient_visit_coverage',
  'approve_facility_data_sharing_agreement',
  'complete_ai_report_request',
  'fail_ai_report_request',
  'create_ai_clinical_session',
  'create_ai_report_request',
  'create_anesthetic_assessment',
  'create_facility_data_sharing_agreement',
  'create_imaging_order_with_payment_gate',
  'create_insurance_claim_draft',
  'create_lab_order_with_payment_gate',
  'create_meal_plan_workflow',
  'create_nursing_care_plan',
  'create_nursing_shift_handover',
  'create_pharmacy_inventory_item',
  'create_service_catalogue_item',
  'create_treatment_template_workflow',
  'create_ward_unit',
  'create_workflow_notification',
  'enqueue_notification_v2',
  'ensure_notification_preferences',
  'get_admission_workspace',
  'get_ai_clinical_context',
  'get_ai_report_requests',
  'get_appointment_clinicians',
  'get_appointment_schedulable_patients',
  'get_appointment_worklist',
  'get_department_queue',
  'get_imaging_workspace',
  'get_insurance_claim_reconciliation_context',
  'get_it_support_system_logs',
  'get_laboratory_workspace',
  'get_my_permissions',
  'get_operational_workspace',
  'get_patient_care_continuity',
  'get_patient_directory',
  'get_patient_directory_record',
  'get_patient_profile_for_user',
  'get_patient_appointments',
  'get_patient_invoice_summary',
  'get_patient_portal_identity',
  'get_patient_telemedicine_clinicians',
  'request_patient_telemedicine_session',
  'get_role_dashboard_summary_for_role',
  'get_ward_management_workspace',
  'import_service_tariffs',
  'import_stg_diagnoses',
  'list_insurance_companies',
  'list_unresolved_clinical_facility_records',
  'list_unresolved_remaining_clinical_facility_records',
  'mark_meal_order_delivered',
  'mark_notification_read',
  'notification_feature_enabled',
  'platform_create_facility',
  'platform_list_facilities',
  'platform_set_user_facility_membership',
  'reconcile_discharge_billing',
  'record_ai_clinical_event',
  'record_notification_consent',
  'record_system_audit',
  'register_patient_workflow',
  'reopen_medication_administration',
  'replace_role_permissions',
  'revoke_facility_data_sharing_agreement',
  'schedule_medication_administration',
  'start_appointment_encounter',
  'start_imaging_order',
  'submit_encounter_workflow',
  'transition_medication_administration',
  'update_encounter_draft_workflow',
  'update_pharmacy_inventory_item',
  'upload_patient_document_metadata',
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
