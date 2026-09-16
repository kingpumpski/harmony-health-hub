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

assert(
  'offline mutations always receive a unique idempotency key',
  offline.includes("const idempotencyKey = crypto.randomUUID();") &&
    offline.includes("[IDEMPOTENCY_HEADER]: idempotencyKey"),
  'queue creation must generate and persist the idempotency header',
);

assert(
  'offline replay restores the persisted idempotency key',
  offline.includes("[IDEMPOTENCY_HEADER]: item.idempotencyKey"),
  'replay must not generate a new key for an existing mutation',
);

assert(
  'offline permanent failures become blocked',
  offline.includes("item.status = 'blocked';") && offline.includes('isPermanentFailure(response.status)'),
  '4xx permanent failures must remain visible for manual resolution',
);

assert(
  'offline transient failures use bounded backoff',
  offline.includes('RETRY_BASE_DELAY_MS') && offline.includes('RETRY_MAX_DELAY_MS') && offline.includes('retryDelayMs(item.attempts)'),
  'retry scheduling must remain bounded and exponential',
);

assert(
  'offline queue preserves the original mutation body during replay',
  offline.includes('body: item.body ?? undefined'),
  'replay must send the persisted payload rather than reconstructing it',
);

const replayStart = offline.indexOf('async function replayMutation');
const retryStart = offline.indexOf('function retryDelayMs', replayStart);
const replaySection = replayStart >= 0 && retryStart > replayStart
  ? offline.slice(replayStart, retryStart)
  : '';

assert(
  'offline replay removes stale authorization before applying the current session',
  /const headers = \{ \.\.\.item\.headers, \[IDEMPOTENCY_HEADER\]: item\.idempotencyKey \};\s*delete headers\.authorization;\s*if \(authHeaderProvider\)/s.test(replaySection) &&
    replaySection.includes('if (accessToken) headers.authorization = `Bearer ${accessToken}`;'),
  'replay must remove persisted Authorization unconditionally before optionally applying a fresh session token',
);

assert(
  'service-order release is database-authoritative',
  workflow.includes("workflowRpc.rpc('release_service_order'") && serviceOrderMigration.includes('FOR UPDATE'),
  'frontend release must delegate to the locked server-side lifecycle function',
);

assert(
  'service-order release enforces payment before release',
  serviceOrderMigration.includes("Payment approval is required before release") &&
    serviceOrderMigration.includes("v_paid < v_order.amount"),
  'unpaid required service orders must not be released without an override',
);

assert(
  'service-order release creates the downstream queue entry',
  serviceOrderMigration.includes('INSERT INTO public.department_queues') &&
    serviceOrderMigration.includes("reason, created_by, queued_at, status") &&
    serviceOrderMigration.includes("'queued'"),
  'released work must become available to the department queue',
);

assert(
  'imaging lifecycle requires server-authoritative start and completion',
  imagingMigration.includes('CREATE OR REPLACE FUNCTION public.start_imaging_order') &&
    imagingMigration.includes('CREATE OR REPLACE FUNCTION public.complete_imaging_order'),
  'imaging start/complete transitions must remain inside SECURITY DEFINER workflow functions',
);

assert(
  'laboratory lifecycle exposes the four guarded workflow stages',
  ['create_lab_order_with_payment_gate', 'collect_lab_sample', 'enter_lab_result', 'approve_lab_result']
    .every((name) => labMigration.includes(`public.${name}`)),
  'lab order, collection, result entry and approval must all remain server-authoritative',
);

assert(
  'database security contract protects lifecycle RPCs',
  securityContract.includes('service-order lifecycle RPCs are security-definer and authenticated-only') &&
    securityContract.includes('laboratory workflow RPCs are security-definer and authenticated-only'),
  'the database contract must continue to assert authenticated-only clinical/financial RPC execution',
);

console.log(`Operational contract checks: ${checks.filter(({ condition }) => condition).length}/${checks.length} passed`);

if (failures.length) {
  console.error('\nContract failures:');
  for (const failure of failures) console.error(`- ${failure}`);
  process.exitCode = 1;
}
