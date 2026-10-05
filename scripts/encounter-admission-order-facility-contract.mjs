#!/usr/bin/env node
import assert from 'node:assert/strict';
import fs from 'node:fs';

const migration = fs.readFileSync(
  'supabase/migrations/20261003092500_harden_encounter_admission_amendment_order_facility_boundary.sql',
  'utf8'
).replace(/\s+/g, ' ').trim().toLowerCase();

for (const fn of [
  'admit_encounter_workflow',
  'amend_encounter_workflow',
  'create_encounter_imaging_order',
  'create_encounter_lab_order',
  'create_encounter_service_order',
  'submit_encounter_workflow'
]) {
  assert(migration.includes('public.' + fn + '('), fn + ': signature must be covered');
  assert(migration.includes('alter function public.' + fn + '('), fn + ': empty search_path must be configured');
  assert(migration.includes('revoke all on function public.' + fn + '('), fn + ': revoke PUBLIC/anon');
  assert(migration.includes('grant execute on function public.' + fn + '('), fn + ': grant authenticated');
}
assert(migration.includes('public.ensure_encounter_facility_attribution(_encounter_id)'), 'shared facility attribution helper must be invoked');
assert(migration.includes("set search_path=''"), 'functions must use an empty search_path');
assert(migration.includes('pg_catalog.strpos(v_definition,v_anchor)'), 'migration must fail closed if a function insertion anchor changes');
assert(migration.includes('test-0001 isolation before admin exceptions'), 'migration must document the test-mode-first contract');
console.log('Encounter admission, amendment, order, and submission facility contract passed.');

const creation = fs.readFileSync(
  'supabase/migrations/20261003095500_harden_encounter_creation_facility_lineage.sql',
  'utf8'
).replace(/\s+/g, ' ').trim().toLowerCase();
for (const needle of [
  'public.create_encounter_workflow(uuid,text,text)',
  'public.assert_patient_facility_context(_patient_id)',
  'and a.facility_id=v_facility',
  'and e.facility_id=v_facility',
  'diagnosis,is_principal,icd_code,ai_suggested,facility_id',
  'select result.id,d.diagnosis,d.is_principal,d.icd_code,d.ai_suggested,v_facility',
  "alter function public.create_encounter_workflow(uuid,text,text) set search_path=''",
  'revoke all on function public.create_encounter_workflow(uuid,text,text) from public,anon',
  'grant execute on function public.create_encounter_workflow(uuid,text,text) to authenticated'
]) {
  assert(creation.includes(needle), 'Encounter creation missing: ' + needle);
}
console.log('Encounter creation facility lineage contract passed.');
