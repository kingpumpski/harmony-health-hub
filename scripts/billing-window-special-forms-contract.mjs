import assert from 'node:assert/strict';
import fs from 'node:fs';

const migrationPath = 'supabase/migrations/20261013150000_fix_billing_window_special_form_qualification.sql';
const migration = fs.readFileSync(migrationPath, 'utf8');

assert.ok(migration.includes("public.prepare_patient_billable_items(uuid,timestamp with time zone,timestamp with time zone)"), 'Target the exact existing billing materialization signature');
assert.ok(migration.includes("pg_catalog.replace(v_definition, 'pg_catalog.coalesce(', 'COALESCE(')"), 'Replace invalid COALESCE qualification');
assert.ok(migration.includes("pg_catalog.replace(v_definition, 'pg_catalog.greatest(', 'GREATEST(')"), 'Replace invalid GREATEST qualification');
assert.ok(migration.includes("pg_catalog.replace(v_definition, 'pg_catalog.least(', 'LEAST(')"), 'Replace invalid LEAST qualification');
assert.ok(migration.includes("RAISE EXCEPTION 'Required billing materialization function is missing'"), 'Fail safely if the target function is missing');
assert.ok(migration.includes('differs from the expected broken definition; review before applying'), 'Fail safely if the live definition has drifted');
assert.ok(!/GRANT\s+EXECUTE|REVOKE\s+ALL|ALTER\s+TABLE/i.test(migration), 'Do not widen privileges or alter schema as part of this repair');

console.log('Billing window special-form migration contract passed');
