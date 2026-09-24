import assert from 'node:assert/strict';
import fs from 'node:fs';

const migration=fs.readFileSync('supabase/migrations/20260924123000_harden_ward_bed_assignment_transfer_boundary.sql','utf8');

const checks=[
 [/patient_id IS NULL/i,'patient existence/required context guard missing'],
 [/status='admitted'/i,'active admission guard missing'],
 [/Admission does not belong to patient/,'admission patient linkage guard missing'],
 [/Patient is already assigned to another occupied bed/,'double-bed assignment guard missing'],
 [/FOR UPDATE/,'row locking missing'],
 [/admission_id=a\.id/,'canonical admission linkage missing'],
 [/UPDATE public\.admissions/,'legacy admission synchronization missing'],
 [/REVOKE ALL ON FUNCTION public\.assign_ward_bed\(uuid,uuid,uuid\) FROM PUBLIC, anon/i,'execute revoke missing'],
 [/GRANT EXECUTE ON FUNCTION public\.assign_ward_bed\(uuid,uuid,uuid\) TO authenticated/i,'authenticated execute grant missing']
];
for (const [pattern,message] of checks) assert.match(migration,pattern,message);
console.log('ward-bed assignment transfer boundary contract passed');
