import fs from 'node:fs';
import assert from 'node:assert/strict';

const migration = fs.readFileSync(
  'supabase/migrations/20260923100000_patient_order_context_hardening.sql',
  'utf8',
);

assert(migration.includes('CREATE OR REPLACE FUNCTION public.create_imaging_order_with_payment_gate'));
assert(migration.includes('CREATE OR REPLACE FUNCTION public.create_lab_order_with_payment_gate'));
assert(migration.includes("COALESCE(status,'active') <> 'inactive'"));
assert(migration.includes("WHERE id = _encounter_id AND patient_id = _patient_id"));
assert(migration.includes("RAISE EXCEPTION 'Encounter does not belong to patient'"));
assert(migration.includes("REVOKE ALL ON FUNCTION public.create_imaging_order_with_payment_gate"));
assert(migration.includes("REVOKE ALL ON FUNCTION public.create_lab_order_with_payment_gate"));
assert(migration.includes('GRANT EXECUTE ON FUNCTION public.create_imaging_order_with_payment_gate'));
assert(migration.includes('GRANT EXECUTE ON FUNCTION public.create_lab_order_with_payment_gate'));
assert(!migration.includes('profiles.role'));
assert(!migration.includes('SELECT role INTO'));

console.log('patient order context hardening contract: PASS');
