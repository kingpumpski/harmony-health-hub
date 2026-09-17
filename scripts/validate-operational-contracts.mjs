import fs from 'node:fs';
import path from 'node:path';

const root = process.cwd();
const read = (relativePath) => fs.readFileSync(path.join(root, relativePath), 'utf8');
const failures = [];
const checks = [];

function assert(name, condition, detail) {
  checks.push({ name, condition });
  if (!condition) failures.push(`${name}: ${detail}`);
}

const offline = read('src/lib/offlineSync.ts');
const workflow = read('src/lib/workflow.ts');
const serviceOrderMigration = read('supabase/migrations/20260916100000_harden_service_order_override_and_release_contract.sql');
const imagingMigration = read('supabase/migrations/20260914130000_imaging_lifecycle_server_authority.sql');
const labMigration = read('supabase/migrations/20260914111500_lab_workflow_payment_gate_reconciliation.sql');
const securityContract = read('supabase/tests/database/security_access_contract.sql');
const securityClassification = read('docs/SECURITY_DEFINER_CLASSIFICATION.md');
const roleGuard = read('src/components/auth/RoleGuard.tsx');
const appRoutes = read('src/App.tsx');
const workflowSummary = read('src/components/WorkflowSummary.tsx');

assert('offline mutations always receive a unique idempotency key', offline.includes("const idempotencyKey = crypto.randomUUID();") && offline.includes("[IDEMPOTENCY_HEADER]: idempotencyKey"), 'queue creation must generate and persist the idempotency header');
assert('offline replay restores the persisted idempotency key', offline.includes("[IDEMPOTENCY_HEADER]: item.idempotencyKey"), 'replay must not generate a new key for an existing mutation');
assert('offline permanent failures become blocked', offline.includes("item.status = 'blocked';") && offline.includes('isPermanentFailure(response.status)'), '4xx permanent failures must remain visible for manual resolution');
assert('offline transient failures use bounded backoff', offline.includes('RETRY_BASE_DELAY_MS') && offline.includes('RETRY_MAX_DELAY_MS') && offline.includes('retryDelayMs(item.attempts)'), 'retry scheduling must remain bounded and exponential');
assert('offline queue preserves the original mutation body during replay', offline.includes('body: item.body ?? undefined'), 'replay must send the persisted payload rather than reconstructing it');

const replayStart = offline.indexOf('async function replayMutation');
const retryStart = offline.indexOf('function retryDelayMs', replayStart);
const replaySection = replayStart >= 0 && retryStart > replayStart ? offline.slice(replayStart, retryStart) : '';
const replayStripsAuthorization = /const headers = \{ \.\.\.item\.headers, \[IDEMPOTENCY_HEADER\]: item\.idempotencyKey \};\s*(?:\/\/[^\n]*\n\s*)*delete headers\.authorization;\s*(?:\/\/[^\n]*\n\s*)*if \(authHeaderProvider\)/s.test(replaySection);
assert('offline replay removes stale authorization before applying the current session', replayStripsAuthorization && replaySection.includes('if (accessToken) headers.authorization = `Bearer ${accessToken}`;'), 'replay must remove persisted Authorization unconditionally before optionally applying a fresh session token');

assert('service-order release is database-authoritative', workflow.includes("workflowRpc.rpc('release_service_order'") && serviceOrderMigration.includes('FOR UPDATE'), 'frontend release must delegate to the locked server-side lifecycle function');
assert('service-order release enforces payment before release', serviceOrderMigration.includes("Payment approval is required before release") && serviceOrderMigration.includes("v_paid < v_order.amount"), 'unpaid required service orders must not be released without an override');
assert('service-order release creates the downstream queue entry', serviceOrderMigration.includes('INSERT INTO public.department_queues') && serviceOrderMigration.includes("reason, created_by, queued_at, status") && serviceOrderMigration.includes("'queued'"), 'released work must become available to the department queue');
assert('imaging lifecycle requires server-authoritative start and completion', imagingMigration.includes('CREATE OR REPLACE FUNCTION public.start_imaging_order') && imagingMigration.includes('CREATE OR REPLACE FUNCTION public.complete_imaging_order'), 'imaging start/complete transitions must remain inside SECURITY DEFINER workflow functions');
assert('laboratory lifecycle exposes the four guarded workflow stages', ['create_lab_order_with_payment_gate', 'collect_lab_sample', 'enter_lab_result', 'approve_lab_result'].every((name) => labMigration.includes(`public.${name}`)), 'lab order, collection, result entry and approval must all remain server-authoritative');
assert('pharmacy lifecycle exposes the protected dispensing and POS workflow surface', ['find_pharmacy_alternatives', 'prepare_pharmacy_dispensing', 'confirm_pharmacy_dispense', 'create_pharmacy_pos_sale', 'confirm_pharmacy_pos_sale', 'create_pharmacy_inventory_item'].every((name) => securityContract.includes(`'${name}'`)), 'pharmacy preparation, dispensing, POS and inventory mutations must remain represented in the database security contract');
assert('insurance lifecycle exposes protected claim mutation workflow', ['create_insurance_claim_draft', 'transition_insurance_claim', 'update_insurance_claim_financials'].every((name) => securityContract.includes(`'${name}'`)), 'insurance claim creation, transition and financial mutation must remain server-authoritative');
assert('selected-invoice payment remains authenticated-only', securityContract.includes("public.pay_selected_invoice_items(uuid,uuid[],text,text)") && securityContract.includes("'selected-invoice payment collection is authenticated-only'"), 'financial payment mutation must not be exposed to anonymous clients');
assert('facility routing changes remain administrator-gated', securityContract.includes("public.set_facility_routing_mode(text)") && securityContract.includes("'facility routing mode is authenticated-only and administrator-gated'") && securityContract.includes("%has_role(auth.uid(),''admin'')%"), 'routing mode changes must remain authenticated-only and explicitly restricted to administrators');
assert('report recovery remains facility-scoped', securityContract.includes("public.recover_stale_report_run(uuid,integer)") && securityContract.includes("'report recovery is authenticated-only and facility-scoped'") && securityContract.includes('%has_facility_access(v_user,v_run.facility_id)%'), 'stale report recovery must not become a cross-facility maintenance endpoint');
assert('selected-invoice payment retains duplicate-reference idempotency', securityContract.includes("'selected-invoice payment rejects duplicate references through an idempotent replay boundary'") && securityContract.includes('%idempotent_replay%'), 'payment retries with the same reference must resolve as an idempotent replay rather than create another payment');
assert('database security contract protects lifecycle RPCs', securityContract.includes('service-order lifecycle RPCs are security-definer and authenticated-only') && securityContract.includes('laboratory workflow RPCs are security-definer and authenticated-only'), 'the database contract must continue to assert authenticated-only clinical/financial RPC execution');

assert('internal SECURITY DEFINER classification register exists', securityClassification.includes('## Explicit internal-only classifications') && securityClassification.includes('audit_patient_change()') && securityClassification.includes('notify_due_medications()') && securityClassification.includes('has_role(uuid, public.app_role)'), 'known internal trigger/scheduler/helper boundaries must remain explicitly classified');
assert('internal trigger execution boundaries are protected by the database contract', securityContract.includes('trigger-only SECURITY DEFINER helpers are outside the client execution surface') && securityContract.includes("public.audit_patient_change()") && securityContract.includes("public.validate_service_order_encounter()"), 'trigger-only SECURITY DEFINER helpers must remain inaccessible to Data API client roles');
assert('scheduler maintenance execution boundaries are protected by the database contract', securityContract.includes('scheduler-only medication maintenance helpers are outside the client execution surface') && securityContract.includes("public.notify_due_medications()") && securityContract.includes("public.lock_overdue_medication_slots()"), 'scheduler-only maintenance functions must remain inaccessible to Data API client roles');
assert('arbitrary-user authorization probes remain outside the client surface', securityContract.includes('arbitrary-user authorization helper probes are outside the client execution surface') && securityContract.includes("public.has_role(uuid,public.app_role)") && securityContract.includes("public.has_facility_access(uuid,uuid)"), 'authorization helpers that accept arbitrary user IDs must not be exposed through the Data API');

assert('protected clinical routes have a client-side role gate', roleGuard.includes('allowedRoles') && appRoutes.includes('<RoleGuard allowedRoles={nursingRoles}>') && appRoutes.includes('<RoleGuard allowedRoles={insuranceRoles}>') && appRoutes.includes('<RoleGuard allowedRoles={emergencyRoles}>') && appRoutes.includes('<RoleGuard allowedRoles={theatreRoles}>') && appRoutes.includes('<RoleGuard allowedRoles={transfusionRoles}>'), 'protected workflow pages must not issue known-forbidden Data API requests for unauthorized roles');
assert('workflow summary avoids known RLS-forbidden admissions reads', workflowSummary.includes("['Occupied beds'") && !workflowSummary.includes("from('admissions')"), 'global dashboard metrics must not directly query admissions where staff SELECT is intentionally restricted');
assert('workflow summary conditionally queries role-protected clinical tables', workflowSummary.includes('canAppointments') && workflowSummary.includes('canBeds') && workflowSummary.includes('canEmergency') && workflowSummary.includes('canTheatre') && workflowSummary.includes('canClaims'), 'dashboard summary reads must follow the same role boundaries as the underlying RLS policies');

console.log(`Operational contract checks: ${checks.filter(({ condition }) => condition).length}/${checks.length} passed`);

if (failures.length) {
  console.error('\nContract failures:');
  for (const failure of failures) console.error(`- ${failure}`);
  process.exitCode = 1;
}