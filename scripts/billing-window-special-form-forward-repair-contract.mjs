import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const migrationPath = new URL('../supabase/migrations/20261127100700_fix_billing_window_special_form_qualification.sql', import.meta.url);
const migration = readFileSync(migrationPath, 'utf8');
const historical = readFileSync(new URL('../supabase/migrations/20261006170000_reconcile_encounter_completion_billing_materialization.sql', import.meta.url), 'utf8');
const deployedContract = readFileSync(new URL('../supabase/tests/database/billing_window_special_forms_contract.sql', import.meta.url), 'utf8');

const identity = "'public.prepare_patient_billable_items(uuid,timestamp with time zone,timestamp with time zone)'::pg_catalog.regprocedure";
assert.ok(migration.includes(identity), 'forward repair must resolve the exact three-argument billing function');
assert.ok(historical.includes('pg_catalog.coalesce('), 'historical source must retain evidence of the original qualification defect');
assert.ok(historical.includes('pg_catalog.greatest('), 'historical source must retain evidence of the original qualification defect');
assert.ok(historical.includes('pg_catalog.least('), 'historical source must retain evidence of the original qualification defect');

for (const form of ['coalesce', 'greatest', 'least']) {
  assert.ok(migration.includes(`'pg_catalog.${form}('`), `migration must count qualified ${form} occurrences`);
  assert.ok(migration.includes(`' ${form.toUpperCase()}('`) || migration.includes(`${form.toUpperCase()}('`), `migration must replace qualified ${form} with its SQL special form`);
}
assert.match(migration, /IF v_coalesce = 0 AND v_greatest = 0 AND v_least = 0 THEN\s+RETURN;/, 'already-correct function must be a no-op');
assert.match(migration, /IF v_coalesce = 0 OR v_greatest = 0 OR v_least = 0 THEN\s+RAISE EXCEPTION/, 'partial source drift must fail closed');
assert.match(migration, /EXECUTE v_definition;/, 'repair must replace only the existing function definition');
assert.doesNotMatch(migration, /CREATE\s+(OR\s+REPLACE\s+)?FUNCTION/i, 'repair must not independently redefine the RPC');
assert.match(deployedContract, /SELECT plan\(5\)/, 'database contract must retain its five assertions');
assert.match(deployedContract, /pg_catalog[.]coalesce|pg_catalog[.]greatest|pg_catalog[.]least/, 'database contract must check the deployed function body');
assert.match(deployedContract, /SECURITY DEFINER and an empty search_path/, 'database contract must pin the security mode');
assert.match(deployedContract, /canonical return shape/, 'database contract must pin the RPC return shape');
assert.match(deployedContract, /denies PUBLIC\/anon execution/, 'database contract must pin execution grants');

console.log('[billing-window-special-form-forward-repair] guarded migration and deployed RPC contract passed');
