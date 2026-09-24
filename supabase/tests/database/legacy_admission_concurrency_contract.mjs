import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';

const sql = execFileSync(
  'supabase',
  ['db','query','--linked','-o','json','select pg_get_functiondef(p.oid) as def from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname=\'public\' and p.proname=\'create_admission_workflow\' and pg_get_function_identity_arguments(p.oid)=\'_patient_id uuid, _ward text, _bed text, _reason text\';'],
  { encoding:'utf8' }
);
const def=JSON.parse(sql).rows?.[0]?.def;
assert.ok(def,'create_admission_workflow definition must exist');
assert.match(def,/pg_advisory_xact_lock\(\s*hashtextextended\(_patient_id::text, 0\)/i);
assert.match(def,/a\.patient_id=_patient_id\s+AND a\.status='admitted'/i);
assert.match(def,/Patient already has an active admission/i);
assert.match(def,/FROM public\.ward_units/i);
assert.doesNotMatch(def,/FROM public\.wards/i);
assert.match(def,/status <> 'available'/i);
assert.match(def,/patient_id IS NOT NULL/i);
assert.match(def,/admission_id IS NOT NULL/i);
assert.match(def,/SET patient_id=_patient_id,\s*admission_id=v_id,\s*status='occupied'/i);
assert.match(def,/status='available'\s*AND patient_id IS NULL\s*AND admission_id IS NULL/i);
assert.match(def,/REVOKE ALL ON FUNCTION public\.create_admission_workflow\(uuid,text,text,text\) FROM PUBLIC, anon/i);
assert.match(def,/GRANT EXECUTE ON FUNCTION public\.create_admission_workflow\(uuid,text,text,text\) TO authenticated/i);
console.log('create admission concurrency/bed consistency contract passed');
