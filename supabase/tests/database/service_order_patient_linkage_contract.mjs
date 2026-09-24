import assert from 'node:assert/strict';
import fs from 'node:fs';

const migration=fs.readFileSync(
  'supabase/migrations/20260923220000_harden_service_order_patient_linkage.sql',
  'utf8',
);

assert.match(migration,/Encounter does not belong to patient/i);
assert.match(migration,/Invoice does not belong to patient/i);
assert.match(migration,/Invoice item does not belong to patient invoice/i);
assert.match(migration,/ii\.invoice_id=_invoice_id/i);
assert.match(migration,/ii\.patient_id=_patient_id/i);
assert.match(migration,/REVOKE ALL ON FUNCTION public\.create_service_order/i);
assert.match(migration,/GRANT EXECUTE ON FUNCTION public\.create_service_order/i);

console.log('service-order patient linkage contract passed');
