import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

const root = process.cwd();
const migrationsDir = path.join(root, 'supabase', 'migrations');
const prerequisiteName = '20260925191900_create_notification_deliveries_table_prerequisite.sql';
const advisorName = '20260925192000_notification_advisor_reconciliation.sql';
const referenceFiles = [
  '20260910215225_restore_missing_reference_tables.sql',
  '20260910215226_reconcile_ai_symptom_icd_map.sql',
  '20260910215227_reconcile_ai_diagnosis_suggestions.sql',
  '20260910215228_81137334-9a88-408e-b7f3-0993eb7b9918.sql',
];
const prerequisitePath = path.join(migrationsDir, prerequisiteName);
const advisorPath = path.join(migrationsDir, advisorName);
const contractPath = path.join(root, 'supabase', 'tests', 'database', 'notification_module_contract.sql');
const referenceContractPath = path.join(root, 'supabase', 'tests', 'database', 'clinical_reference_prerequisite_contract.sql');
const workflowPath = path.join(root, '.github', 'workflows', 'migration-contract.yml');

for (const file of [prerequisitePath, advisorPath, contractPath, referenceContractPath, workflowPath,
  ...referenceFiles.map((name) => path.join(migrationsDir, name))]) {
  assert.ok(fs.existsSync(file), 'Required migration contract file missing: ' + path.relative(root, file));
}

const migrationFiles = fs.readdirSync(migrationsDir).filter((name) => name.endsWith('.sql'));
const versions = (name) => name.match(/^(\d{14})_/u)?.[1] ?? null;
for (const name of [...referenceFiles, prerequisiteName, advisorName]) {
  assert.ok(versions(name), 'Invalid migration version prefix: ' + name);
  assert.equal(migrationFiles.filter((candidate) => versions(candidate) === versions(name)).length, 1,
    'Migration version collision for ' + versions(name));
}
assert.ok(versions(referenceFiles[0]) < versions(referenceFiles[1]), 'Reference table prerequisites are out of order');
assert.ok(versions(referenceFiles[1]) < versions(referenceFiles[2]), 'Symptom map must precede diagnosis suggestions');
assert.ok(versions(referenceFiles[2]) < versions(referenceFiles[3]), 'Clinical reference tables must precede RLS hardening');
assert.ok(versions(prerequisiteName) < versions(advisorName), 'Delivery prerequisite must execute before advisor reconciliation');

const prerequisite = fs.readFileSync(prerequisitePath, 'utf8');
const advisor = fs.readFileSync(advisorPath, 'utf8');
const contract = fs.readFileSync(contractPath, 'utf8');
const referenceContract = fs.readFileSync(referenceContractPath, 'utf8');
const workflowText = fs.readFileSync(workflowPath, 'utf8');

assert.match(prerequisite, /CREATE TABLE IF NOT EXISTS public\.notification_deliveries/u);
assert.match(prerequisite, /ENABLE ROW LEVEL SECURITY/u);
assert.match(prerequisite, /REVOKE ALL ON TABLE public\.notification_deliveries FROM PUBLIC, anon, authenticated/u);
assert.match(prerequisite, /GRANT ALL ON TABLE public\.notification_deliveries TO service_role/u);
assert.doesNotMatch(advisor, /public\.notification_channel_preferences|public\.notification_push_subscriptions/u,
  'Advisor migration must not target obsolete notification relations');
assert.match(advisor, /ON public\.notification_deliveries\(user_id\)/u);
assert.match(contract, /notification_devices must have RLS enabled/u);
assert.match(contract, /notification_deliveries must have RLS enabled/u);
assert.match(contract, /anon must not read notification delivery evidence/u);
assert.match(contract, /authenticated must not read notification delivery evidence/u);
assert.ok(workflowText.includes('supabase test db supabase/tests/database/notification_module_contract.sql'));

const referenceSql = referenceFiles.map((name) => fs.readFileSync(path.join(migrationsDir, name), 'utf8'));
const hardeningSql = referenceSql[3];
for (const [index, table] of [
  [0, 'audit_logs'], [0, 'sync_queue'], [0, 'lab_tests'],
  [1, 'ai_symptom_icd_map'], [2, 'ai_diagnosis_suggestions'],
]) {
  assert.ok(referenceSql[index].toLowerCase().includes('create table if not exists public.' + table),
    'Missing prerequisite CREATE TABLE for ' + table);
  assert.ok(hardeningSql.includes('ALTER TABLE public.' + table + ' ENABLE ROW LEVEL SECURITY'),
    'Missing RLS enablement for ' + table);
}
assert.ok(hardeningSql.includes('DROP POLICY IF EXISTS "clinical staff manage ai diagnosis suggestions"'));
assert.ok(hardeningSql.includes('DROP POLICY IF EXISTS "admins read audit logs"'));
assert.ok(hardeningSql.includes('DROP POLICY IF EXISTS "admins read sync queue"'));
assert.ok(hardeningSql.includes("relkind = 'v'"), 'Optional legacy views must be guarded before ALTER VIEW');
assert.ok(hardeningSql.includes('GRANT SELECT, INSERT, UPDATE, DELETE ON public.ai_symptom_icd_map TO authenticated'));
assert.ok(hardeningSql.includes('GRANT SELECT, INSERT, UPDATE, DELETE ON public.lab_tests TO authenticated'));
assert.ok(referenceContract.includes('must have RLS enabled'));
assert.ok(referenceContract.includes('anon/public policies must not expose'));
assert.ok(workflowText.includes('supabase test db supabase/tests/database/clinical_reference_prerequisite_contract.sql'));

console.log('Clinical reference prerequisites, RLS, grants, and notification migration contracts passed.');
