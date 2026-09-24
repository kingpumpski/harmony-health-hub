import assert from 'node:assert/strict';
import fs from 'node:fs';

const migration = fs.readFileSync(
  'supabase/migrations/20260924110000_harden_bill_materialization_patient_context.sql',
  'utf8',
);

const checks = [
  [/invoice_items\([\s\S]*invoice_id,patient_id,description/, 'generated invoice items do not populate patient_id'],
  [/service_order_id\)\s*\n\s*\s*SELECT[\s\S]*r\.id/, 'service-order invoice items are not canonically linked'],
  [/so\.invoice_item_id IS NULL/, 'already-linked service orders are not excluded'],
  [/Service order % is linked to a different invoice/, 'cross-invoice service-order guard missing'],
  [/SET invoice_id=inv,\s*\n\s*invoice_item_id=r\.invoice_item_id/, 'service-order back-link missing'],
  [/so\.patient_id=_patient_id/, 'return service-order patient boundary missing'],
  [/pg_advisory_xact_lock/, 'patient materialization serialization missing'],
  [/REVOKE ALL ON FUNCTION public\.prepare_patient_billable_items\(uuid,timestamptz,timestamptz\) FROM PUBLIC, anon/i, 'execute revoke missing'],
  [/GRANT EXECUTE ON FUNCTION public\.prepare_patient_billable_items\(uuid,timestamptz,timestamptz\) TO authenticated/i, 'authenticated execute grant missing'],
];

for (const [pattern, message] of checks) assert.match(migration, pattern, message);

console.log('bill materialization patient-context contract passed');
