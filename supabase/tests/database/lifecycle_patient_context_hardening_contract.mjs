import assert from 'node:assert/strict';
import fs from 'node:fs';

const path='supabase/migrations/20260923170000_lifecycle_patient_context_hardening.sql';
const s=fs.readFileSync(path,'utf8');

for (const name of ['transition_emergency_case','transition_theatre_case','record_transfusion_event']) {
  assert(s.includes(`CREATE OR REPLACE FUNCTION public.${name}`), `${name} override exists`);
}
assert((s.match(/COALESCE\(status,'active'\)<>'inactive'/g)||[]).length >= 3, 'all lifecycle transitions reject inactive patients');
assert(s.includes('c.patient_id') && s.includes('r.patient_id'), 'lifecycle rows resolve their patient context');
assert(s.includes('c.encounter_id') && s.includes('r.encounter_id'), 'linked encounter context remains guarded');
assert(s.includes('REVOKE ALL ON FUNCTION public.transition_emergency_case(UUID,TEXT,TEXT) FROM PUBLIC,anon'), 'emergency transition is not anonymous');
assert(s.includes('REVOKE ALL ON FUNCTION public.transition_theatre_case(UUID,TEXT,TEXT) FROM PUBLIC,anon'), 'theatre transition is not anonymous');
assert(s.includes('REVOKE ALL ON FUNCTION public.record_transfusion_event(UUID,TEXT,BOOLEAN,TEXT) FROM PUBLIC,anon'), 'transfusion transition is not anonymous');
console.log('lifecycle patient-context hardening contract: ok');
