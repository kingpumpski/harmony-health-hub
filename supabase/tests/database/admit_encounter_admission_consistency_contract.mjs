import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';

const sql = execFileSync(
  'supabase',
  ['db','query','--linked','-o','json','select pg_get_functiondef(p.oid) as def from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname=\'public\' and p.proname=\'admit_encounter_workflow\' and pg_get_function_identity_arguments(p.oid)=\'_encounter_id uuid, _reason text, _ward text, _emergency_override boolean\';'],
  { encoding: 'utf8' }
);

const row = JSON.parse(sql).rows?.[0];
assert.ok(row?.def, 'admit_encounter_workflow definition must exist');
const def = row.def;

assert.match(def, /FROM public\.encounters WHERE id=_encounter_id\s+FOR UPDATE/i);
assert.match(def, /pg_advisory_xact_lock\(\s*hashtextextended\(v_enc\.patient_id::text, 0\)/i);
assert.match(def, /a\.patient_id=v_enc\.patient_id\s+AND a\.status='admitted'/i);
assert.match(def, /Patient already has an active inpatient admission/i);
assert.match(def, /FROM public\.ward_units/i);
assert.doesNotMatch(def, /INSERT INTO public\.wards/i);
assert.match(def, /Ward not found in canonical ward units/i);
assert.match(def, /v_ward_id/i);
assert.match(def, /Encounter admission linkage is inconsistent/i);
assert.match(def, /REVOKE ALL ON FUNCTION public\.admit_encounter_workflow\(uuid,text,text,boolean\) FROM PUBLIC, anon/i);
assert.match(def, /GRANT EXECUTE ON FUNCTION public\.admit_encounter_workflow\(uuid,text,text,boolean\) TO authenticated/i);

console.log('admit encounter ward/admission consistency contract passed');
