import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

const root = process.cwd();
const migrationsDir = path.join(root, 'supabase', 'migrations');
const prerequisiteName = '20260925191900_create_notification_deliveries_table_prerequisite.sql';
const advisorName = '20260925192000_notification_advisor_reconciliation.sql';
const prerequisitePath = path.join(migrationsDir, prerequisiteName);
const advisorPath = path.join(migrationsDir, advisorName);
const contractPath = path.join(root, 'supabase', 'tests', 'database', 'notification_module_contract.sql');
const workflowPath = path.join(root, '.github', 'workflows', 'migration-contract.yml');

for (const file of [prerequisitePath, advisorPath, contractPath, workflowPath]) {
  assert.ok(fs.existsSync(file), 'Required notification migration contract file missing: ' + path.relative(root, file));
}

const migrationFiles = fs.readdirSync(migrationsDir).filter((name) => name.endsWith('.sql'));
const versions = (name) => name.match(/^(\d{14})_/u)?.[1] ?? null;
for (const name of [prerequisiteName, advisorName]) {
  assert.ok(versions(name), 'Invalid migration version prefix: ' + name);
  assert.equal(migrationFiles.filter((candidate) => versions(candidate) === versions(name)).length, 1,
    'Migration version collision for ' + versions(name));
}
assert.ok(versions(prerequisiteName) < versions(advisorName), 'Delivery prerequisite must execute before advisor reconciliation');

const prerequisite = fs.readFileSync(prerequisitePath, 'utf8');
const advisor = fs.readFileSync(advisorPath, 'utf8');
const contract = fs.readFileSync(contractPath, 'utf8');
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
assert.match(workflowText, /supabase test db supabase\/tests\/database\/notification_module_contract\.sql/u);

console.log('Notification migration prerequisite, ordering, RLS, and CI contracts passed.');
