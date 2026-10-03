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
