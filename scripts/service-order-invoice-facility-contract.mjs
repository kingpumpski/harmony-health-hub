#!/usr/bin/env node
import assert from 'node:assert/strict';
import fs from 'node:fs';

const sql = fs.readFileSync(
  'supabase/migrations/20261003101500_harden_service_order_and_invoice_facility_boundaries.sql',
  'utf8'
).replace(/\s+/g, ' ').trim().toLowerCase();

for (const fn of ['cancel_service_order', 'complete_service_order', 'adjust_invoice_item_tariff']) {
  assert(sql.includes("revoke all on function %s from public, anon"), fn + ': public/anon execution must be revoked');
  assert(sql.includes("grant execute on function %s to authenticated"), fn + ': authenticated execution must be explicit');
}
assert(sql.includes('public.assert_patient_facility_context(v_patient_id)'), 'service-order mutations must enforce patient facility/test-mode context');
assert(sql.includes('v_order_facility is distinct from v_patient_facility'), 'service-order facility must match patient facility');
assert(sql.includes('public.assert_patient_facility_context(item.patient_id)'), 'tariff adjustments must enforce patient facility/test-mode context');
assert(sql.includes('item.facility_id is distinct from item.invoice_facility_id'), 'invoice item and invoice facility must match');
assert(sql.includes('s.facility_id=item.facility_id'), 'linked service-order updates must remain within the invoice item facility');
assert(sql.includes('set search_path to %l'), 'functions must pin search_path');
console.log('Service-order and invoice facility-boundary contract passed.');
