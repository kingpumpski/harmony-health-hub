#!/usr/bin/env node
import assert from 'node:assert/strict';
import fs from 'node:fs';

const sql = fs.readFileSync(
  'supabase/migrations/20261003094000_harden_direct_patient_order_facility_boundary.sql',
  'utf8'
).replace(/\s+/g, ' ').trim().toLowerCase();

for (const fn of [
  'create_lab_order_with_payment_gate',
  'create_imaging_order_with_payment_gate',
  'create_service_order'
]) {
  assert(sql.includes('alter function public.' + fn + '('), fn + ': empty search_path');
  assert(sql.includes('revoke all on function public.' + fn + '('), fn + ': revoke public/anon');
  assert(sql.includes('grant execute on function public.' + fn + '('), fn + ': authenticated grant');
}
assert(sql.includes('public.assert_patient_facility_context(_patient_id)'), 'patient facility assertion must be used by direct order RPCs');
assert(sql.includes('e.facility_id=(select p.facility_id from public.patients p where p.id=_patient_id)'), 'service order encounter must match patient facility');
assert(sql.includes('created_by,facility_id) values'), 'service order must persist facility attribution');
assert(sql.includes('test-0001 isolation in directly callable service-order and lab/imaging order helpers'), 'documented test-mode boundary');
console.log('Direct patient, lab, imaging, and service order facility contract passed.');
