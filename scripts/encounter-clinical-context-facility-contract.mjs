#!/usr/bin/env node
import fs from 'node:fs';
const migration=fs.readFileSync('supabase/migrations/20261002201000_harden_encounter_clinical_context_facility_boundary.sql','utf8').replace(/\s+/g,' ').trim().toLowerCase();
for(const n of [
'create or replace function public.get_encounter_clinical_context(_patient_id uuid, _encounter_id uuid default null::uuid)',
'security definer','set search_path = \'\'','auth.uid()','public.hms_test_mode_enabled()',
'public.hms_test_facility_id()','public.current_user_facility_id()',
'e.facility_id=v_test_facility','e.facility_id=v_facility',
'revoke all on function public.get_encounter_clinical_context(uuid, uuid) from public, anon',
'grant execute on function public.get_encounter_clinical_context(uuid, uuid) to authenticated'
]) if(!migration.includes(n)) throw new Error('Missing clinical context boundary: '+n);
const testIndex=migration.indexOf('if public.hms_test_mode_enabled()');
const nonTestIndex=migration.indexOf('elsif not public.has_role(v_user,\'admin\')');
if(testIndex<0||nonTestIndex<0||testIndex>nonTestIndex) throw new Error('Clinical context must evaluate test-mode isolation before non-test admin exception');
console.log('Encounter clinical context facility boundary contract passed.');
