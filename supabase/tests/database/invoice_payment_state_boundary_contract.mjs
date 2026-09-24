import assert from 'node:assert/strict';
import fs from 'node:fs';

const migration=fs.readFileSync(
  'supabase/migrations/20260924073000_harden_invoice_payment_state_boundary.sql',
  'utf8',
);

assert.match(migration,/FOR UPDATE;[\s\S]*IF NOT FOUND THEN RAISE EXCEPTION 'Invoice not found'/i);
assert.match(migration,/invoice_status NOT IN \('pending','partially_paid'\)/i);
assert.match(migration,/invoice_patient_id IS NULL/i);
assert.match(migration,/id=ANY\(_item_ids\)/i);
assert.match(migration,/REVOKE ALL ON FUNCTION public\.pay_selected_invoice_items\(uuid,uuid\[\],text,text\)/i);
assert.match(migration,/GRANT EXECUTE ON FUNCTION public\.pay_selected_invoice_items\(uuid,uuid\[\],text,text\) TO authenticated/i);

console.log('invoice payment state boundary contract passed');
