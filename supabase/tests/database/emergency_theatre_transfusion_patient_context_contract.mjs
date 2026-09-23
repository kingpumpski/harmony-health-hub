import fs from 'node:fs'; import assert from 'node:assert/strict';
const s=fs.readFileSync('supabase/migrations/20260923143000_emergency_theatre_transfusion_patient_context.sql','utf8');
for(const fn of ['create_emergency_case','create_theatre_case','create_transfusion_record','assign_ward_bed']) assert(s.includes('CREATE OR REPLACE FUNCTION public.'+fn),fn+' missing');
assert((s.match(/COALESCE\(status,'active'\)<>'inactive'/g)||[]).length>=4,'inactive patient guards missing');
assert(s.includes("v_patient<>_patient_id"),'encounter patient binding missing');
assert(s.includes("admission_patient<>_patient_id"),'admission patient binding missing');
assert((s.match(/REVOKE ALL ON FUNCTION/g)||[]).length>=4,'execution revokes missing');
console.log('emergency/theatre/transfusion/bed patient context contract: PASS');