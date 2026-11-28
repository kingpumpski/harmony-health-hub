import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const lockdown = readFileSync(new URL('../supabase/migrations/20260912250000_lab_direct_write_lockdown.sql', import.meta.url), 'utf8');
const finalization = readFileSync(new URL('../supabase/migrations/20260912250000_reconciliation_finalization.sql', import.meta.url), 'utf8');

for (const table of ['lab_orders', 'lab_results']) {
  assert.ok(lockdown.includes(`REVOKE INSERT, UPDATE, DELETE ON public.${table} FROM authenticated;`), `lab lockdown must revoke direct writes on ${table}`);
  assert.ok(finalization.includes(`REVOKE INSERT, UPDATE, DELETE ON public.${table} FROM authenticated;`), `finalization must preserve direct-write revocation on ${table}`);
}
assert.ok(lockdown.includes('REVOKE UPDATE ON public.lab_orders FROM authenticated;'), 'lab catalogue linkage must not be directly updated');
for (const signature of [
  'public.collect_lab_sample(UUID)',
  'public.enter_lab_result(UUID,TEXT,NUMERIC,TEXT,BOOLEAN)',
  'public.approve_lab_result(UUID)',
  'public.attach_lab_catalogue_to_order(UUID,UUID)'
]) {
  assert.ok(lockdown.includes(`REVOKE EXECUTE ON FUNCTION ${signature} FROM anon;`), `anon execution must be revoked for ${signature}`);
  assert.ok(!finalization.includes(`GRANT EXECUTE ON FUNCTION ${signature}`), `finalization must not restore anon execution for ${signature}`);
}
const writeProtectedTables = [
  'emergency_cases','theatre_cases','transfusion_records','insurance_claims',
  'nursing_care_plans','nursing_shift_handovers','ward_units','ward_beds',
  'medication_administrations','prescriptions'
];
for (const table of writeProtectedTables) {
  assert.ok(finalization.includes(`REVOKE INSERT, UPDATE, DELETE ON public.${table} FROM authenticated;`), `finalization must revoke direct writes on ${table}`);
}
assert.ok(finalization.includes('GRANT SELECT ON public.lab_orders, public.lab_results TO authenticated;'), 'lab clinical read access must be preserved explicitly');
assert.ok(finalization.includes('GRANT SELECT ON public.emergency_cases, public.theatre_cases, public.transfusion_records,'), 'HIMS clinical read access must be preserved explicitly');
assert.doesNotMatch(lockdown + '\n' + finalization, /GRANT\s+(?:INSERT|UPDATE|DELETE|ALL)\b/i, 'neither colliding migration may restore direct write grants');
assert.doesNotMatch(lockdown + '\n' + finalization, /CREATE\s+POLICY|DROP\s+POLICY|ENABLE\s+ROW\s+LEVEL\s+SECURITY/i, 'ACL pair must not silently alter RLS policy semantics');
console.log('[migration-20260912250000-acl] direct-write revocations, read grants and anon RPC revocations are consistent');
