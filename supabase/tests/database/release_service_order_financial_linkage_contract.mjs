import assert from 'node:assert/strict';
import fs from 'node:fs';

const migration = fs.readFileSync(
  'supabase/migrations/20260924103000_harden_release_service_order_financial_linkage.sql',
  'utf8',
);

const checks = [
  [/v_order\.patient_id IS NULL/, 'service-order patient guard missing'],
  [/v_item\.patient_id IS NULL/, 'invoice-item patient guard missing'],
  [/v_item\.patient_id IS DISTINCT FROM v_order\.patient_id/, 'invoice-item/service-order patient linkage guard missing'],
  [/v_item\.invoice_id IS DISTINCT FROM v_order\.invoice_id/, 'invoice-item/invoice linkage guard missing'],
  [/v_item\.service_order_id IS NOT NULL AND v_item\.service_order_id IS DISTINCT FROM v_order\.id/, 'cross-service-order linkage guard missing'],
  [/SET service_order_id=v_order\.id/, 'missing canonical invoice-item back-link repair'],
  [/FOR UPDATE/, 'release financial rows are not locked'],
  [/REVOKE ALL ON FUNCTION public\.release_service_order\(uuid,text\) FROM PUBLIC, anon/i, 'execute revoke missing'],
  [/GRANT EXECUTE ON FUNCTION public\.release_service_order\(uuid,text\) TO authenticated/i, 'authenticated execute grant missing'],
];

for (const [pattern, message] of checks) assert.match(migration, pattern, message);

console.log('release service-order financial linkage contract passed');
