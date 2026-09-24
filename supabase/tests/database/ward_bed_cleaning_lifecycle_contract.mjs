import assert from 'node:assert/strict';
import fs from 'node:fs';

const migration=fs.readFileSync('supabase/migrations/20260924130000_harden_ward_bed_cleaning_lifecycle.sql','utf8');

const checks=[
 [/status <> 'cleaning'/i,'cleaning-state guard missing'],
 [/b\.patient_id IS NOT NULL OR b\.admission_id IS NOT NULL/i,'patient/admission context guard missing'],
 [/status='available'/i,'available transition missing'],
 [/patient_id IS NULL/i,'patient-clearance invariant missing'],
 [/admission_id IS NULL/i,'admission-clearance invariant missing'],
 [/FOR UPDATE/i,'bed row locking missing'],
 [/REVOKE ALL ON FUNCTION public\.complete_ward_bed_cleaning\(uuid,text\) FROM PUBLIC, anon/i,'execute revoke missing'],
 [/GRANT EXECUTE ON FUNCTION public\.complete_ward_bed_cleaning\(uuid,text\) TO authenticated/i,'authenticated execute grant missing']
];
for (const [pattern,message] of checks) assert.match(migration,pattern,message);
console.log('ward-bed cleaning lifecycle contract passed');
