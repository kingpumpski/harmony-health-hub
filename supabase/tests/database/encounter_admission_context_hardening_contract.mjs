import assert from 'node:assert/strict'; import fs from 'node:fs';
const s=fs.readFileSync('supabase/migrations/20260923133000_encounter_admission_context_hardening.sql','utf8');
for(const n of ['create_encounter_prescription','set_principal_diagnosis','create_admission_workflow','discharge_admission_workflow']) assert(s.includes('CREATE OR REPLACE FUNCTION public.'+n),n);
assert((s.match(/COALESCE\(status,'active'\)<>'inactive'/g)||[]).length>=2,'patient inactivity guards');
assert(s.includes('Diagnosis does not belong to encounter'),'diagnosis binding');
assert(s.includes('patient_id_value'),'prescription derives patient from encounter');
assert((s.match(/REVOKE ALL ON FUNCTION/g)||[]).length===4,'execution hardening');
assert(!s.includes('profiles.role')&&!s.includes('SELECT role INTO'),'no legacy single-role lookup');
console.log('encounter admission context hardening contract: PASS');