import fs from 'node:fs';
const root=new URL('../../',import.meta.url);
const migration=fs.readFileSync(new URL('migrations/20260924141000_harden_inpatient_occupancy_invariants.sql',root),'utf8');
const checks=[
['active admission uniqueness',/admissions_one_active_per_patient_uniq/i.test(migration)],
['one occupied bed per patient',/ward_beds_one_occupied_per_patient_uniq/i.test(migration)],
['one occupied bed per admission',/ward_beds_one_occupied_per_admission_uniq/i.test(migration)],
['patient advisory lock',/pg_advisory_xact_lock\(hashtextextended\(_patient_id::text,0\)\)/i.test(migration)],
['bed row lock',/FROM public\.ward_beds WHERE id=_bed_id FOR UPDATE/i.test(migration)],
['active admission requirement',/status='admitted'/i.test(migration)],
['linked occupied bed',/patient_id=_patient_id,admission_id=a\.id,status='occupied'/i.test(migration)],
['null links rejected',/AND patient_id IS NULL AND admission_id IS NULL/i.test(migration)],
['authenticated only',/REVOKE ALL ON FUNCTION public\.assign_ward_bed\(uuid,uuid,uuid\) FROM PUBLIC,anon/i.test(migration)]
];
for(const [name,ok] of checks)if(!ok)throw new Error('Failed contract: '+name);
console.log('Inpatient occupancy invariants contract passed.');