import fs from 'node:fs';
import path from 'node:path';

const root = process.cwd();
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8');
const failures = [];
let passed = 0;
function check(name, condition, detail) {
  if (condition) passed += 1;
  else failures.push(`${name}: ${detail}`);
}

const files = {
  offline: read('src/lib/offlineSync.ts'),
  workflow: read('src/lib/workflow.ts'),
  serviceOrder: read('supabase/migrations/20260916100000_harden_service_order_override_and_release_contract.sql'),
  imaging: read('supabase/migrations/20260914130000_imaging_lifecycle_server_authority.sql'),
  lab: read('supabase/migrations/20260914111500_lab_workflow_payment_gate_reconciliation.sql'),
  security: read('supabase/tests/database/security_access_contract.sql'),
  classification: read('docs/SECURITY_DEFINER_CLASSIFICATION.md'),
  roleGuard: read('src/components/auth/RoleGuard.tsx'),
  routes: read('src/App.tsx'),
  summary: read('src/components/WorkflowSummary.tsx'),
  import: read('src/pages/admin/DataImport.tsx'),
  foundation: read('supabase/migrations/20260917120000_expand_master_data_migration_and_legacy_records.sql'),
  importRpcs: read('supabase/migrations/20260917120500_add_reference_data_import_rpcs.sql'),
  importGrants: read('supabase/migrations/20260917113500_harden_reference_data_import_rpc_grants.sql'),
  migrationCenter: read('src/pages/admin/MigrationReconciliationCenter.tsx'),
  reconciliation: read('supabase/migrations/20260917133000_add_migration_reconciliation_workflows.sql'),
  triage: read('src/pages/Triage.tsx'),
  encounters: read('src/pages/Encounters.tsx'),
};

const hasAll = (text, values) => values.every((value) => text.includes(value));
const route = (path, role) => `<Route path="${path}" element={<RoleGuard allowedRoles={${role}>`;

check('offline idempotency creation', files.offline.includes('crypto.randomUUID()') && files.offline.includes('IDEMPOTENCY_HEADER'), 'offline mutations need persisted unique idempotency keys');
check('offline replay persistence', files.offline.includes('item.idempotencyKey') && files.offline.includes('body: item.body ?? undefined'), 'replay must reuse the persisted key and body');
check('offline failure handling', files.offline.includes("item.status = 'blocked'") && files.offline.includes('isPermanentFailure'), 'permanent failures must remain visible for resolution');
check('offline bounded retry', hasAll(files.offline, ['RETRY_BASE_DELAY_MS','RETRY_MAX_DELAY_MS','retryDelayMs(item.attempts)']), 'transient replay must use bounded backoff');
check('service order server authority', files.workflow.includes("workflowRpc.rpc('release_service_order'") && files.serviceOrder.includes('FOR UPDATE'), 'release must remain database-authoritative');
check('service order payment gate', files.serviceOrder.includes('Payment approval is required before release') && files.serviceOrder.includes('v_paid < v_order.amount'), 'unpaid orders require approval or override');
check('service order queue', hasAll(files.serviceOrder, ['INSERT INTO public.department_queues','reason, created_by, queued_at, status',"'queued'"]), 'released work must enter the department queue');
check('imaging authority', hasAll(files.imaging, ['CREATE OR REPLACE FUNCTION public.start_imaging_order','CREATE OR REPLACE FUNCTION public.complete_imaging_order']), 'imaging transitions must remain server-authoritative');
check('lab lifecycle', hasAll(files.lab, ['create_lab_order_with_payment_gate','collect_lab_sample','enter_lab_result','approve_lab_result']), 'all laboratory workflow stages must remain represented');
check('pharmacy security contract', hasAll(files.security, ['find_pharmacy_alternatives','prepare_pharmacy_dispensing','confirm_pharmacy_dispense','create_pharmacy_pos_sale','confirm_pharmacy_pos_sale','create_pharmacy_inventory_item']), 'pharmacy mutations require security-contract coverage');
check('insurance security contract', hasAll(files.security, ['create_insurance_claim_draft','transition_insurance_claim','update_insurance_claim_financials']), 'insurance mutations require security-contract coverage');
check('payment authentication', files.security.includes('pay_selected_invoice_items(uuid,uuid[],text,text)') && files.security.includes('selected-invoice payment collection is authenticated-only'), 'payment collection must not be anonymous');
check('internal classification', hasAll(files.classification, ['audit_patient_change()','notify_due_medications()','has_role(uuid, public.app_role)']), 'internal SECURITY DEFINER boundaries must be classified');
check('trigger security', files.security.includes('trigger-only SECURITY DEFINER helpers are outside the client execution surface'), 'trigger helpers must not be client-callable');
check('scheduler security', files.security.includes('scheduler-only medication maintenance helpers are outside the client execution surface'), 'scheduler helpers must not be client-callable');
check('authorization helper security', files.security.includes('arbitrary-user authorization helper probes are outside the client execution surface'), 'authorization probes must not be client-callable');
check('clinical role gates', hasAll(files.roleGuard, ['allowedRoles']) && hasAll(files.routes, ['clinicalRoles','nursingRoles','insuranceRoles','emergencyRoles','theatreRoles','transfusionRoles']), 'protected clinical routes need role gates');
check('laboratory route gate', hasAll(files.routes, ['const laboratoryRoles','/laboratory','/results-entry']), 'laboratory routes need the clinical laboratory boundary');
check('pharmacy route gate', hasAll(files.routes, ["const pharmacyRoles = ['admin', 'pharmacist']",'/pharmacy','/inventory']), 'pharmacy routes need the pharmacy boundary');
check('MAR route gate', files.routes.includes('/medications') && files.routes.includes('allowedRoles={clinicalRoles}'), 'MAR route needs clinical authorization');
check('maternity route gate', files.routes.includes('/maternity') && files.routes.includes('allowedRoles={nursingRoles}'), 'maternity route needs nursing authorization');
check('diagnostic route gates', hasAll(files.routes, ['/imaging','/procedures','/anesthesia']), 'diagnostic/procedure routes need clinical authorization');
check('AI/admin gates', hasAll(files.routes, ['/ai-clinical','/admin/users','allowedRoles={clinicalRoles}']), 'AI and user-management surfaces need explicit role boundaries');
check('accounts gate', hasAll(files.routes, ['const accountsRoles','/accounts-approvals']), 'accounts approvals need a financial role boundary');
check('reports gate', hasAll(files.routes, ['const reportsRoles','/reports','/reports/submissions']), 'reporting routes need an administrator boundary');
check('workflow summary avoids admissions', files.summary.includes("['Occupied beds'") && !files.summary.includes("from('admissions')"), 'global dashboard must not bypass admissions RLS');
check('workflow summary role-aware', hasAll(files.summary, ['canAppointments','canBeds','canEmergency','canTheatre','canClaims']), 'dashboard reads must follow table role boundaries');
check('migration domains', hasAll(files.import, ['stg_diagnoses','service_tariffs','legacy_clinical_records']), 'data import must cover STG, tariffs and legacy records');
check('migration staging', files.import.includes('stage_data_migration_rows') && files.foundation.includes('CREATE TABLE IF NOT EXISTS public.legacy_clinical_records'), 'legacy records must be staged before promotion');
check('migration admin control', files.foundation.includes('admins manage migration batches') && files.foundation.includes('Administrator access required'), 'migration controls must be administrator-only');
check('reference import RPCs', hasAll(files.import, ['import_stg_diagnoses','import_service_tariffs']) && hasAll(files.importRpcs, ['REVOKE ALL ON FUNCTION public.import_stg_diagnoses','REVOKE ALL ON FUNCTION public.import_service_tariffs']), 'reference data imports require governed RPCs');
check('reference RPC grants', hasAll(files.importGrants, ['FROM anon','import_stg_diagnoses','import_service_tariffs','create_data_migration_batch']), 'anonymous clients must not execute migration RPCs');
check('master data catalogue', hasAll(files.foundation, ['CREATE TABLE IF NOT EXISTS public.system_master_data','domain,code,source_system']), 'master-data catalogue must exist');
check('triage empty state', files.triage.includes("useState('')") && hasAll(files.triage, ['90–120 mmHg','60–80 mmHg','95–100 %']), 'vitals must begin empty and show normal reference placeholders');
check('triage alerts', hasAll(files.triage, ['Immediate clinical attention required','value > range.high','role="alert"']), 'abnormal vitals must alert before save');
check('encounter three-column workspace', hasAll(files.encounters, ['lg:grid-cols-[minmax(240px,320px)_minmax(0,1fr)_minmax(280px,360px)]','Encounter history','New encounter entry','Patient safety']), 'encounter page must keep history, entry and safety context in the requested layout');
check('reconciliation matching workflow', hasAll(files.reconciliation, ['find_legacy_patient_candidates','reconcile_legacy_record_patient','validate_legacy_record']), 'legacy records need controlled matching and validation workflows');
check('reconciliation state', hasAll(files.reconciliation, ['match_confidence','match_method','validation_errors','reconciled_by','reconciled_at']), 'legacy records need auditable reconciliation state');
check('reconciliation center', hasAll(files.migrationCenter, ['data_migration_batches','data_migration_rows','legacy_clinical_records']), 'administrator review surface must expose staged migration data');
check('reconciliation route', files.routes.includes('/admin/migration-reconciliation') && files.routes.includes('MigrationReconciliationCenter'), 'reconciliation center must be administrator-gated');

console.log(`Operational contract checks: ${passed}/40 passed`);
if (failures.length) {
  console.error('\nContract failures:');
  failures.forEach((failure) => console.error(`- ${failure}`));
  process.exitCode = 1;
}
