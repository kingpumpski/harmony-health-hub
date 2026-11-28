import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const sql = readFileSync(new URL('../supabase/tests/database/billing_window_special_forms_contract.sql', import.meta.url), 'utf8');

assert.match(sql, /public[.]prepare_patient_billable_items[(]uuid,timestamp with time zone,timestamp with time zone[)]'::regprocedure/, 'database contract must target the exact deployed billing function');
for (const form of ['coalesce', 'greatest', 'least']) {
  assert.match(sql, new RegExp('pg_catalog[.]' + form + '[(]'), 'database contract must reject qualified ' + form);
  assert.ok(sql.includes("NOT ILIKE '%pg_catalog." + form + "(%'"), 'database contract must fail when qualified ' + form + ' remains');
}
assert.match(sql, /SELECT plan[(]5[)]/, 'database contract must declare its assertion plan');

console.log('[billing-window-special-forms] deployed function catalog contract passed');
