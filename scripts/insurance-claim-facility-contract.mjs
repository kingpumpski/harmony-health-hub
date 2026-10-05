#!/usr/bin/env node
import assert from 'node:assert/strict';
import fs from 'node:fs';

const sql = fs.readFileSync(
  'supabase/migrations/20261003111500_harden_insurance_claim_facility_boundaries.sql',
  'utf8'
).replace(/\s+/g, ' ').trim().toLowerCase();

for (const fn of [
  'transition_insurance_claim_canonical',
  'update_insurance_claim_financials',
  'update_insurance_case'
]) {
  assert(sql.includes(`public.${fn}(`), fn + ': function must be hardened');
}
assert(sql.includes('public.assert_patient_facility_context(c.patient_id)'), 'claim mutations must enforce patient/test-mode context');
assert(sql.includes('c.facility_id is distinct from'), 'claim facility must match patient facility');
assert(sql.includes('i.facility_id=c.facility_id'), 'claim invoice must match claim facility');
assert(sql.includes('public.assert_patient_facility_context(v_patient_id)'), 'insurance case mutation must enforce patient/test-mode context');
assert(sql.includes('v_case_facility is distinct from v_patient_facility'), 'insurance case facility must match patient facility');
assert(sql.includes('revoke all on function %s from public, anon'), 'public/anon execution must be revoked');
assert(sql.includes('grant execute on function %s to authenticated'), 'authenticated execution must be explicit');
console.log('Insurance claim facility-boundary contract passed.');
