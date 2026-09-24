import fs from 'node:fs'; import assert from 'node:assert/strict';
const s=fs.readFileSync('supabase/migrations/20260923150000_medication_patient_context_hardening.sql','utf8');
for(const fn of ['schedule_medication_administration','transition_medication_administration']) assert(s.includes('CREATE OR REPLACE FUNCTION public.'+fn),fn+' override missing');
assert((s.match(/COALESCE\(status,'active'\)<>'inactive'/g)||[]).length>=2,'inactive patient guards missing');
assert(s.includes("p.patient_id<>r.patient_id"),'prescription/patient binding missing');
assert(s.includes("r.status<>'scheduled'"),'duplicate MAR transition guard missing');
assert(s.includes("REVOKE ALL ON FUNCTION public.schedule_medication_administration"),'schedule execute revoke missing');
assert(s.includes("REVOKE ALL ON FUNCTION public.transition_medication_administration"),'transition execute revoke missing');
console.log('medication patient context hardening contract: PASS');