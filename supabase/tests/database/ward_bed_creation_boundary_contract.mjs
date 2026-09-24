import assert from 'node:assert/strict';
import fs from 'node:fs';

const migration=fs.readFileSync('supabase/migrations/20260924131000_harden_ward_bed_creation_boundary.sql','utf8');
const checks=[
 [/FROM public\.ward_units/i,'canonical ward-unit lookup missing'],
 [/active=true/i,'inactive ward guard missing'],
 [/Bed number already exists in this ward/i,'duplicate bed guard missing'],
 [/status,patient_id,admission_id/i,'safe initial bed state missing'],
 [/REVOKE ALL ON FUNCTION public\.create_ward_bed\(uuid,text\) FROM PUBLIC, anon/i,'execute revoke missing'],
 [/GRANT EXECUTE ON FUNCTION public\.create_ward_bed\(uuid,text\) TO authenticated/i,'authenticated execute grant missing']
];
for (const [pattern,message] of checks) assert.match(migration,pattern,message);
console.log('ward-bed creation boundary contract passed');
