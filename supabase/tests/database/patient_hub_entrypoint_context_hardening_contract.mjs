import assert from 'node:assert/strict';
import fs from 'node:fs';

const s = fs.readFileSync('supabase/migrations/20260923130000_patient_hub_entrypoint_context_hardening.sql','utf8');
for (const name of ['create_encounter_workflow','record_patient_vitals','create_patient_lab_order','create_patient_document']) {
  assert(s.includes(`CREATE OR REPLACE FUNCTION public.${name}`), `${name} override exists`);
}
assert((s.match(/COALESCE\(status,'active'\) <> 'inactive'/g)||[]).length >= 4, 'all four entrypoints reject inactive patients');
assert((s.match(/auth\.uid\(\) IS NULL/g)||[]).length >= 4, 'all four entrypoints require authentication');
assert((s.match(/REVOKE ALL ON FUNCTION/g)||[]).length >= 4, 'all four entrypoints revoke public execution');
assert(!s.includes('profiles.role'));
assert(!s.includes('SELECT role INTO'));
console.log('patient hub entrypoint context hardening contract: PASS');
