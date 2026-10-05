#!/usr/bin/env node
import assert from 'node:assert/strict';
import fs from 'node:fs';

const sql = fs.readFileSync(
  'supabase/migrations/20261003104000_harden_billing_workflow_facility_boundaries.sql',
  'utf8'
).replace(/\s+/g, ' ').trim().toLowerCase();

for (const fn of [
  'grant_service_order_override',
  'mark_billing_items_billed',
  'mark_service_order_in_progress',
  'pay_selected_invoice_items',
  'release_service_order'
]) {
  assert(sql.includes(`public.${fn}(`), fn + ': function must be explicitly hardened');
}
assert(sql.includes('public.assert_patient_facility_context(v_order.patient_id)'), 'service-order transitions must enforce patient facility and test-mode context');
assert(sql.includes('v_order.facility_id is distinct from v_patient_facility'), 'service-order facility must match patient facility');
assert(sql.includes('public.assert_patient_facility_context(v_patient_id)'), 'invoice mutations must enforce patient facility and test-mode context');
assert(sql.includes('v_invoice_facility is distinct from v_patient_facility'), 'invoice facility must match patient facility');
assert(sql.includes('ii.facility_id is distinct from v_invoice_facility'), 'selected invoice items must match invoice facility');
assert(sql.includes('service_code,facility_id)'), 'legacy payment path must write service-order facility attribution');
assert(sql.includes('item.service_code,v_invoice_facility)'), 'legacy payment path must use the invoice facility');
assert(sql.includes('revoke all on function %s from public, anon'), 'public and anon execution must be revoked');
assert(sql.includes('grant execute on function %s to authenticated'), 'authenticated execution must be explicit');
console.log('Billing workflow facility-boundary contract passed.');
