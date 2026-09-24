import assert from 'node:assert/strict';
import fs from 'node:fs';

const migration=fs.readFileSync('supabase/migrations/20260924133000_harden_ward_bed_release_consistency.sql','utf8');

const checks=[
 [/FOR UPDATE/i,'bed locking missing'],
 [/Bed admission patient context mismatch/i,'patient-admission consistency guard missing'],
 [/Discharge or transfer the active admission before releasing this bed/i,'active-admission release guard missing'],
 [/status = 'occupied'/i,'occupied-bed state guard missing'],
 [/status = 'cleaning'/i,'cleaning transition missing'],
 [/updated_at = now\(\)/i,'bed update timestamp missing'],
 [/REVOKE ALL ON FUNCTION public\.release_ward_bed\(uuid, text\) FROM PUBLIC, anon/i,'execute revoke missing'],
 [/GRANT EXECUTE ON FUNCTION public\.release_ward_bed\(uuid, text\) TO authenticated/i,'authenticated execute grant missing']
];

for (const [pattern,message] of checks) assert.match(migration,pattern,message);
console.log('ward-bed release consistency contract passed');
