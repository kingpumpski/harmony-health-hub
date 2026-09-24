import assert from 'node:assert/strict';
import fs from 'node:fs';

const migration=fs.readFileSync('supabase/migrations/20260924120000_harden_discharge_ward_bed_consistency.sql','utf8');

const checks=[
 [/FROM public\.ward_beds wb/, 'canonical ward-bed lookup missing'],
 [/wb\.admission_id=a\.id/, 'bed-to-admission linkage guard missing'],
 [/wb\.patient_id=a\.patient_id/, 'bed-to-patient linkage guard missing'],
 [/status='cleaning'/, 'discharged bed is not transitioned to cleaning'],
 [/patient_id=NULL,\s*admission_id=NULL/, 'bed patient/admission links are not cleared'],
 [/updated_at=now\(\)/, 'ward-bed update timestamp missing'],
 [/ward_bed_released/, 'discharge audit does not record bed release'],
 [/REVOKE ALL ON FUNCTION public\.discharge_admission_workflow\(uuid,text\) FROM PUBLIC, anon/i, 'execute revoke missing'],
 [/GRANT EXECUTE ON FUNCTION public\.discharge_admission_workflow\(uuid,text\) TO authenticated/i, 'authenticated execute grant missing']
];

for (const [pattern,message] of checks) assert.match(migration,pattern,message);
console.log('discharge ward-bed consistency contract passed');
