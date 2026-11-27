import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const base = new URL('../supabase/migrations/', import.meta.url);
const enterprise = readFileSync(new URL('20260912024500_global_hims_enterprise_operations.sql', base), 'utf8');
const global = readFileSync(new URL('20260912024500_global_hims_inpatient_emergency_theatre_insurance.sql', base), 'utf8');

function policy(source, name) {
  const statement = source.split(';').find(part => part.includes('CREATE POLICY "' + name + '"'));
  assert.ok(statement, 'Missing policy: ' + name);
  return statement.trim() + ';';
}

const pairs = [
  ['nursing care plans clinical', 'nursing care plan access'],
  ['handover clinical', 'nursing handover access'],
  ['emergency clinical', 'emergency clinical access'],
  ['theatre clinical', 'theatre clinical access'],
  ['transfusion clinical', 'transfusion clinical access'],
];

for (const [enterpriseName, globalName] of pairs) {
  const a = policy(enterprise, enterpriseName);
  const b = policy(global, globalName);
  assert.match(a, /FOR ALL TO authenticated/i);
  assert.match(b, /FOR ALL TO authenticated/i);
  assert.match(a, /USING\s*\(/i);
  assert.match(b, /USING\s*\(/i);
  assert.match(a, /WITH CHECK\s*\(/i);
  assert.match(b, /WITH CHECK\s*\(/i);
  assert.ok(!/facility_id|active_facility|current_facility/i.test(a), enterpriseName + ' has no explicit facility predicate');
  assert.ok(!/facility_id|active_facility|current_facility/i.test(b), globalName + ' has no explicit facility predicate');
}

// PostgreSQL permissive policies are OR-combined. These source policies overlap on the same
// five shared tables and can therefore widen access if both migrations are applied.
assert.equal(pairs.length, 5);
assert.match(enterprise, /ALTER TABLE public\\.nursing_care_plans ENABLE ROW LEVEL SECURITY/i);
assert.match(global, /ALTER TABLE public\\.nursing_care_plans ENABLE ROW LEVEL SECURITY/i);

const globalCare = policy(global, 'nursing care plan access');
const enterpriseCare = policy(enterprise, 'nursing care plans clinical');
assert.match(globalCare, /created_by = auth\\.uid\(\)/i);
assert.match(enterpriseCare, /WITH CHECK\s*\(public\\.has_role/i);
assert.match(policy(global, 'nursing handover access'), /outgoing_officer = auth\\.uid\(\)/i);
assert.match(policy(global, 'emergency clinical access'), /assigned_officer = auth\\.uid\(\)/i);
assert.match(policy(global, 'theatre clinical access'), /created_by = auth\\.uid\(\)/i);
assert.match(policy(global, 'transfusion clinical access'), /administered_by = auth\\.uid\(\)/i);

console.log('[migration-20260912024500-rls] PASS: five colliding policy pairs are pinned; permissive OR-combination and missing facility predicates remain explicit release blockers.');
