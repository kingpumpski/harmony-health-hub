#!/usr/bin/env node
import fs from 'node:fs';
const migration=fs.readFileSync('supabase/migrations/20261002204500_harden_encounter_facility_attribution_and_diagnosis.sql','utf8').replace(/\s+/g,' ').trim().toLowerCase();
for(const n of [
'create or replace function public.ensure_encounter_facility_attribution(_encounter_id uuid)',
'security definer',"set search_path = ''",'public.hms_test_mode_enabled()','public.hms_test_facility_id()','public.current_user_facility_id()',
'revoke all on function public.ensure_encounter_facility_attribution(uuid) from public, anon',
'create or replace function public.add_encounter_diagnosis(','public.ensure_encounter_facility_attribution(_encounter_id)',
'revoke all on function public.add_encounter_diagnosis(uuid,text,text) from public, anon'
]) if(!migration.includes(n)) throw new Error('Missing diagnosis boundary: '+n);
const test=migration.indexOf('if public.hms_test_mode_enabled()');
const nonTest=migration.indexOf('else v_facility:=public.current_user_facility_id()');
if(test<0||nonTest<0||test>nonTest) throw new Error('Test-mode boundary must precede non-test facility handling');
console.log('Encounter facility attribution and diagnosis contract passed.');
