#!/usr/bin/env node
import fs from 'node:fs';
const migration=fs.readFileSync('supabase/migrations/20261002194500_add_encounter_worklist_read_rpc.sql','utf8').replace(/\s+/g,' ').trim().toLowerCase();
const ui=fs.readFileSync('src/pages/Encounters.tsx','utf8');
for(const n of ['create or replace function public.get_encounter_worklist(_limit integer default 50)','stable security definer','set search_path = \'\'','auth.uid() is not null','public.hms_test_mode_enabled()','public.hms_test_facility_id()','public.current_user_facility_id()','revoke all on function public.get_encounter_worklist(integer) from public, anon','grant execute on function public.get_encounter_worklist(integer) to authenticated']) if(!migration.includes(n)) throw new Error('Missing encounter worklist control: '+n);
if(!ui.includes('db.rpc("get_encounter_worklist"')) throw new Error('Encounters page must use the protected encounter worklist RPC');
if (ui.includes('supabase.from("encounters")') || ui.includes("supabase.from('encounters')")) throw new Error('Encounters page must not directly query encounters');
console.log('Encounter worklist RPC contract passed.');
