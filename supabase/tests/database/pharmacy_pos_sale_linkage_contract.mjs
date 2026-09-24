import assert from 'node:assert/strict';
import fs from 'node:fs';

const migration=fs.readFileSync(
  'supabase/migrations/20260924070000_harden_pharmacy_pos_sale_linkage.sql',
  'utf8',
);

assert.match(migration,/order_row\.patient_id IS DISTINCT FROM result\.patient_id/i);
assert.match(migration,/order_row\.related_entity_id IS DISTINCT FROM result\.id/i);
assert.match(migration,/order_row\.order_type IS DISTINCT FROM 'drug'/i);
assert.match(migration,/POS sale service order does not match sale/i);
assert.match(migration,/REVOKE ALL ON FUNCTION public\.confirm_pharmacy_pos_sale\(uuid\)/i);
assert.match(migration,/GRANT EXECUTE ON FUNCTION public\.confirm_pharmacy_pos_sale\(uuid\) TO authenticated/i);

console.log('pharmacy POS sale linkage contract passed');
