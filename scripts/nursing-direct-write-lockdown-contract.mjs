import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const migrationPath = 'supabase/migrations/20261127103000_lock_nursing_lifecycle_table_writes.sql';
const migration = readFileSync(migrationPath, 'utf8');
const ledger = JSON.parse(readFileSync('supabase/migration-ledger-baseline.json', 'utf8'));
const migrationVersion = /^([0-9]{14})_/.exec(migrationPath.split('/').at(-1) ?? '')?.[1];
assert.ok(migrationVersion && migrationVersion > ledger.latest_version, 'forward repair must sort after the verified hosted migration ledger');
const packageJson = JSON.parse(readFileSync('package.json', 'utf8'));
const handoverUi = readFileSync('src/pages/NursingHandover.tsx', 'utf8');
const nurseDashboard = readFileSync('src/pages/dashboard/NurseDashboard.tsx', 'utf8');
const clinicalOperations = readFileSync('src/pages/ClinicalOperations.tsx', 'utf8');
const clinicalAssist = readFileSync('supabase/functions/ai-clinical-assist/index.ts', 'utf8');

assert.match(migration, /REVOKE ALL ON TABLE public\.nursing_shift_handovers FROM PUBLIC, anon/i);
assert.match(migration, /REVOKE INSERT, UPDATE, DELETE ON TABLE public\.nursing_shift_handovers FROM authenticated/i);
assert.match(migration, /REVOKE ALL ON TABLE public\.nursing_care_plans FROM PUBLIC, anon/i);
assert.match(migration, /REVOKE INSERT, UPDATE, DELETE ON TABLE public\.nursing_care_plans FROM authenticated/i);
assert.match(migration, /GRANT SELECT ON TABLE public\.nursing_shift_handovers TO authenticated/i);
assert.match(migration, /GRANT SELECT ON TABLE public\.nursing_care_plans TO authenticated/i);
assert.doesNotMatch(migration, /\b(DROP|TRUNCATE)\s+(TABLE|COLUMN|CONSTRAINT|INDEX)\b/i);

assert.match(handoverUi, /supabase\.rpc\('create_nursing_shift_handover'/);
assert.match(handoverUi, /supabase\.rpc\('acknowledge_nursing_handover'/);
assert.match(clinicalOperations, /supabase\.rpc\('create_nursing_care_plan'/);
assert.match(nurseDashboard, /supabase\.functions\.invoke\('ai-clinical-assist'/);
assert.match(clinicalAssist, /from\('nursing_shift_handovers'\)\.select\(/);
for (const [label, source, table] of [
  ['handover page', handoverUi, 'nursing_shift_handovers'],
  ['nurse dashboard', nurseDashboard, 'nursing_shift_handovers'],
  ['clinical operations', clinicalOperations, 'nursing_care_plans'],
  ['clinical-assist edge function', clinicalAssist, 'nursing_shift_handovers'],
]) {
  const directMutation = new RegExp(String.raw`\.from\(['"]${table}['"]\)\s*\.\s*(insert|update|upsert|delete)\b`, 'i');
  assert.doesNotMatch(source, directMutation, `${label} must not mutate ${table} directly`);
}

assert.match(packageJson.scripts.test, /test:nursing-direct-write-lockdown/);
assert.equal(packageJson.scripts['test:nursing-direct-write-lockdown'], 'node scripts/nursing-direct-write-lockdown-contract.mjs');

console.log('Nursing lifecycle direct-write lockdown contract passed.');
