import assert from 'node:assert/strict';
import fs from 'node:fs';

const migration = fs.readFileSync(
  'supabase/migrations/20260924100000_harden_tariff_adjustment_service_order_linkage.sql',
  'utf8',
);

const checks = [
  [/item\.invoice_patient_id IS NULL/, 'invoice patient context guard missing'],
  [/item\.patient_id IS NOT NULL AND item\.patient_id IS DISTINCT FROM item\.invoice_patient_id/, 'invoice-item patient linkage guard missing'],
  [/linked_service_order_id := item\.service_order_id/, 'canonical invoice-item service-order link not preferred'],
  [/Service order patient does not match invoice patient/, 'service-order patient guard missing'],
  [/Service order invoice does not match invoice item invoice/, 'service-order invoice guard missing'],
  [/Service order invoice item does not match invoice item/, 'service-order invoice-item guard missing'],
  [/FOR UPDATE/, 'tariff adjustment locking missing'],
  [/billing_tariff_adjustments[\s\S]*service_order_id/, 'tariff adjustment audit linkage missing'],
  [/REVOKE ALL ON FUNCTION public\.adjust_invoice_item_tariff\(uuid,numeric,text,text\) FROM PUBLIC, anon/i, 'execute revoke missing'],
  [/GRANT EXECUTE ON FUNCTION public\.adjust_invoice_item_tariff\(uuid,numeric,text,text\) TO authenticated/i, 'authenticated execute grant missing'],
];

for (const [pattern, message] of checks) assert.match(migration, pattern, message);

console.log('tariff adjustment service-order linkage contract passed');
