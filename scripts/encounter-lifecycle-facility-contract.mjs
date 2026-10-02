#!/usr/bin/env node
import assert from 'node:assert/strict';
import fs from 'node:fs';

const files = [
  'supabase/migrations/20261002210000_harden_diagnosis_lifecycle_facility_boundary.sql',
  'supabase/migrations/20261002211500_harden_encounter_draft_completion_prescription_facility_boundary.sql'
];

for (const file of files) {
  const s = fs.readFileSync(file, 'utf8').replace(/\s+/g, ' ').trim().toLowerCase();
  assert(s.includes('security definer'), file + ': security definer');
  assert(s.includes("set search_path=''"), file + ': empty search_path');
  assert(s.includes('public.hms_test_mode_enabled()'), file + ': test mode guard');
  assert(s.includes('public.hms_test_facility_id()'), file + ': test facility guard');
  assert(s.includes('public.current_user_facility_id()'), file + ': active facility guard');
  assert(s.includes('revoke all on function'), file + ': public/anon revoke');
  assert(s.includes('grant execute on function'), file + ': authenticated grant');
}

const diagnosis = fs.readFileSync(files[0], 'utf8').replace(/\s+/g, ' ').trim().toLowerCase();
const diagnosisTest = diagnosis.indexOf('if public.hms_test_mode_enabled()');
const diagnosisAdmin = diagnosis.indexOf("if not(public.has_role(uid,'admin') or public.has_role(uid,'it_admin'))");
assert(diagnosisTest >= 0 && diagnosisAdmin > diagnosisTest, 'diagnosis test-mode check must precede non-test privileged exception');

const workflow = fs.readFileSync(files[1], 'utf8').replace(/\s+/g, ' ').trim().toLowerCase();
for (const fn of ['save_encounter_draft','complete_encounter_workflow','create_encounter_prescription']) {
  const i = workflow.indexOf('create or replace function public.' + fn);
  assert(i >= 0, fn + ': declaration');
  const body = workflow.slice(i, workflow.indexOf('$function$;', i));
  assert(body.includes('if public.hms_test_mode_enabled()'), fn + ': test-mode-first guard');
  assert(body.includes('public.hms_test_facility_id()'), fn + ': test facility');
}
console.log('Encounter diagnosis, draft, completion, and prescription facility-boundary contracts passed.');
