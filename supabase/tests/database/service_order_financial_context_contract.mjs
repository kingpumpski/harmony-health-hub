import assert from 'node:assert/strict';
import fs from 'node:fs';

const migration=fs.readFileSync(
  'supabase/migrations/20260924080000_harden_service_order_financial_context.sql',
  'utf8',
);

assert.match(migration,/Encounter does not belong to patient/i);
assert.match(migration,/Invoice does not belong to patient/i);
assert.match(migration,/Invoice does not match encounter/i);
assert.match(migration,/Invoice item does not belong to patient/i);
assert.match(migration,/Invoice item does not belong to invoice/i);
assert.match(migration,/Invoice item is already linked to a service order/i);
assert.match(migration,/service_order_id=v_order\.id/i);
assert.match(migration,/REVOKE ALL ON FUNCTION public\.create_service_order\(uuid,uuid,text,text,numeric,uuid,text,uuid,uuid,uuid,text,text\)/i);
assert.match(migration,/GRANT EXECUTE ON FUNCTION public\.create_service_order\(uuid,uuid,text,text,numeric,uuid,text,uuid,uuid,uuid,text,text\) TO authenticated/i);

console.log('service order financial context contract passed');
