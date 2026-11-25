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


const databaseContractPath = 'supabase/tests/database/billing_window_special_forms_contract.sql';
const databaseContract = fs.readFileSync(databaseContractPath, 'utf8');
assert.ok(databaseContract.includes('SELECT plan(5);'), 'Database contract must cover all five billing invariants');
assert.ok(databaseContract.includes("p.proconfig @> ARRAY['search_path=\"\"']"), 'Database contract must verify empty search_path');
assert.ok(databaseContract.includes('pg_get_function_result('), 'Database contract must verify the canonical return shape');
assert.ok(databaseContract.includes("has_function_privilege('authenticated'"), 'Database contract must verify authenticated execution');
assert.ok(databaseContract.includes("has_function_privilege('anon'"), 'Database contract must verify anonymous execution is denied');
assert.ok(databaseContract.includes('a.grantee = 0'), 'Database contract must verify PUBLIC execution is denied');

console.log('Billing window special-form migration contract passed');
