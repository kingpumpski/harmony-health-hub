#!/usr/bin/env node
import assert from 'node:assert/strict';
import fs from 'node:fs';

const migrationPath = 'supabase/migrations/20261003111500_harden_insurance_claim_facility_boundaries.sql';
const migration = fs.readFileSync(migrationPath, 'utf8');
const sql = migration.replace(/\s+/g, ' ').trim().toLowerCase();
assert(!sql.includes('\\n'), 'SQL normalization must collapse line breaks before structural checks');
const facilityBackfillPattern = /update\\s+public\\.(insurance_claims|invoices)\\s+set\\s+facility_id/i;
assert(facilityBackfillPattern.test('UPDATE\\n public.insurance_claims\\n SET\\n facility_id = patient_facility_id'), 'facility backfill guard must recognize multiline SQL');


const claimSignatures = [
  'public.transition_insurance_claim_canonical(uuid,text,numeric,numeric,text,text)',
  'public.update_insurance_claim_financials(uuid,numeric,numeric,text,text)',
];

for (const signature of claimSignatures) {
  assert(sql.includes(signature), signature + ': exact claim RPC signature must be covered');
}

for (const fn of [
  'transition_insurance_claim_canonical',
  'update_insurance_claim_financials',
  'update_insurance_case'
]) {
  assert(sql.includes(`public.${fn}(`), fn + ': function must be hardened');
}

assert(sql.includes("v_anchor := 'if c.id is null then raise exception ''claim not found''; end if;'"), 'claim hardening must fail closed when the expected source anchor is absent');
assert(sql.includes('public.assert_patient_facility_context(c.patient_id)'), 'claim mutations must enforce patient/test-mode context');
assert(sql.includes('c.facility_id is distinct from'), 'claim facility must match patient facility');
assert(sql.includes('i.facility_id=c.facility_id'), 'claim invoice must match claim facility');
assert(sql.includes('i.patient_id=c.patient_id'), 'claim invoice must match the claim patient');
assert(sql.includes('insurance claim invoice does not match patient and facility'), 'invoice lineage mismatch must be rejected explicitly');
assert(sql.includes("alter function %s set search_path to %l"), 'each rewritten claim function must receive an explicit pinned search_path');
assert(sql.includes("'pg_catalog, public'"), 'claim functions must use the reviewed pinned search_path');
assert(sql.includes('revoke all on function %s from public, anon'), 'public/anon execution must be revoked');
assert(sql.includes('grant execute on function %s to authenticated'), 'authenticated execution must be explicit');

assert(sql.includes('public.assert_patient_facility_context(v_patient_id)'), 'insurance case mutation must enforce patient/test-mode context');
assert(sql.includes('v_case_facility is distinct from v_patient_facility'), 'insurance case facility must match patient facility');
assert(sql.includes('if v_patient_facility is null'), 'unresolved patient facility must fail closed');
assert(!/update\s+public\.(insurance_claims|invoices)\s+set\s+facility_id/i.test(migration), 'facility hardening must not silently backfill historical claims or invoices');

console.log('Insurance claim facility-boundary contract passed.');
