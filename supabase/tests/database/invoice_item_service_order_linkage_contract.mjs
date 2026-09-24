import assert from 'node:assert/strict';
import fs from 'node:fs';

const migration=fs.readFileSync(
  'supabase/migrations/20260924083000_harden_invoice_item_service_order_linkage.sql',
  'utf8',
);

assert.match(migration,/Invoice must be open and linked to a patient/i);
assert.match(migration,/Invoice item does not belong to invoice patient/i);
assert.match(migration,/Service order does not match invoice patient or invoice/i);
assert.match(migration,/Service order does not match invoice item/i);
assert.match(migration,/service_order_id=order_row\.id/i);
assert.match(migration,/REVOKE ALL ON FUNCTION public\.pay_selected_invoice_items/i);
assert.match(migration,/GRANT EXECUTE ON FUNCTION public\.pay_selected_invoice_items/i);

console.log('invoice item service order linkage contract passed');
