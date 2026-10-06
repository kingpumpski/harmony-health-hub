#!/usr/bin/env node
import fs from 'node:fs';
import assert from 'node:assert/strict';

const normalize = path => fs.readFileSync(path, 'utf8').replace(/\s+/g, ' ').trim().toLowerCase();
const attribution = normalize('supabase/migrations/20261002204500_harden_encounter_facility_attribution_and_diagnosis.sql');
for (const n of [
  'create or replace function public.ensure_encounter_facility_attribution(_encounter_id uuid)',
  'security definer', "set search_path = ''", 'public.hms_test_mode_enabled()',
  'public.hms_test_facility_id()', 'public.current_user_facility_id()',
  'revoke all on function public.ensure_encounter_facility_attribution(uuid) from public, anon',
  'create or replace function public.add_encounter_diagnosis(',
  'public.ensure_encounter_facility_attribution(_encounter_id)',
  'revoke all on function public.add_encounter_diagnosis(uuid,text,text) from public, anon'
]) assert(attribution.includes(n), 'Missing diagnosis attribution boundary: ' + n);
const attrTest = attribution.indexOf('if public.hms_test_mode_enabled()');
const attrNonTest = attribution.indexOf('else v_facility := public.current_user_facility_id()');
assert(attrTest >= 0 && attrNonTest > attrTest, 'Attribution must check test mode before non-test facility handling');

const lifecycle = normalize('supabase/migrations/20261002210000_harden_diagnosis_lifecycle_facility_boundary.sql');
for (const fn of ['set_principal_diagnosis', 'remove_encounter_diagnosis']) {
  const start = lifecycle.indexOf('create or replace function public.' + fn + '(');
  assert(start >= 0, fn + ': function declaration');
  const end = lifecycle.indexOf('$function$;', start);
  assert(end > start, fn + ': function body terminator');
  const body = lifecycle.slice(start, end);
  for (const guard of ['security definer', "set search_path=''", 'auth.uid()', 'public.hms_test_mode_enabled()', 'public.hms_test_facility_id()', 'public.current_user_facility_id()']) {
    assert(body.includes(guard), fn + ': missing ' + guard);
  }
  assert(body.includes("if public.hms_test_mode_enabled()"), fn + ': test-mode-first guard');
}
for (const signature of [
  'revoke all on function public.set_principal_diagnosis(uuid,uuid) from public,anon',
  'grant execute on function public.set_principal_diagnosis(uuid,uuid) to authenticated',
  'revoke all on function public.remove_encounter_diagnosis(uuid) from public,anon',
  'grant execute on function public.remove_encounter_diagnosis(uuid) to authenticated'
]) assert(lifecycle.includes(signature), 'Missing lifecycle execute privilege contract: ' + signature);

console.log('Encounter facility attribution, diagnosis write, and diagnosis lifecycle contracts passed.');

const encounters=fs.readFileSync('src/pages/Encounters.tsx','utf8');
if(!encounters.includes('db.rpc("add_encounter_diagnosis", { _encounter_id: selected.id, _diagnosis: newDx.trim(), _icd_code: null })')) throw new Error('Encounters must call canonical three-argument diagnosis RPC');
console.log('Verified canonical Encounters diagnosis RPC transport.');
