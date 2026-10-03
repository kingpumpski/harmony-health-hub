#!/usr/bin/env node
import fs from 'node:fs';

const migration = fs.readFileSync(
  'supabase/migrations/20261002203000_harden_encounter_clerking_facility_boundary.sql',
  'utf8'
).replace(/\s+/g, ' ').trim().toLowerCase();

for (const needle of [
  'create or replace function public.save_encounter_clerking(',
  'returns public.encounters',
  'security definer',
  "set search_path = ''",
  'auth.uid()',
  "public.has_role(uid, 'practitioner')",
  'public.hms_test_mode_enabled()',
  'public.hms_test_facility_id()',
  'public.current_user_facility_id()',
  'v_encounter.facility_id is distinct from public.hms_test_facility_id()',
  'v_patient_facility is distinct from public.hms_test_facility_id()',
  'revoke all on function public.save_encounter_clerking(uuid,text,text,text,text,text,text,text,date) from public, anon',
  'grant execute on function public.save_encounter_clerking(uuid,text,text,text,text,text,text,text,date) to authenticated'
]) {
  if (!migration.includes(needle)) throw new Error('Missing clerking boundary: ' + needle);
}

const testIndex = migration.indexOf('if public.hms_test_mode_enabled()');
const privilegedExceptionIndex = migration.indexOf(
  "if public.has_role(uid, 'admin') or public.has_role(uid, 'it_admin') then"
);
if (testIndex < 0 || privilegedExceptionIndex < 0 || testIndex > privilegedExceptionIndex) {
  throw new Error('Clerking must evaluate test-mode isolation before privileged-role exception');
}

console.log('Encounter clerking facility boundary contract passed.');
