import assert from 'node:assert/strict';
import fs from 'node:fs';

const migration=fs.readFileSync('supabase/migrations/20260924113000_harden_admission_ward_bed_compatibility.sql','utf8');
const checks=[
 [/FROM public\.wards/, 'ward registry validation missing'],
 [/FROM public\.ward_beds/, 'canonical ward-bed validation missing'],
 [/Bed not found in selected ward/, 'bed-to-ward validation missing'],
 [/Selected bed is not available/, 'bed availability guard missing'],
 [/a\.patient_id=_patient_id[\s\S]*a\.status='admitted'/, 'duplicate active admission guard missing'],
 [/status='occupied'/, 'ward bed occupancy update missing'],
 [/admission_id=v_id/, 'admission-to-bed linkage missing'],
 [/REVOKE ALL ON FUNCTION public\.create_admission_workflow\(uuid,text,text,text\) FROM PUBLIC, anon/i, 'execute revoke missing'],
 [/GRANT EXECUTE ON FUNCTION public\.create_admission_workflow\(uuid,text,text,text\) TO authenticated/i, 'authenticated execute grant missing']
];
for(const [p,m] of checks) assert.match(migration,p,m);
console.log('admission ward-bed compatibility contract passed');
