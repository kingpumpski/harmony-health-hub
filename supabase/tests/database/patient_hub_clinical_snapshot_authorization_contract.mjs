import fs from 'node:fs';

const migration = fs.readFileSync(
  'supabase/migrations/20260921084058_add_patient_hub_clinical_snapshot.sql',
  'utf8'
);
const lock = fs.readFileSync(
  'supabase/migrations/20260921084116_lock_patient_hub_clinical_snapshot_execute.sql',
  'utf8'
);

for (const role of ['admin','practitioner','nurse','midwife','specialist_nurse','lab_technician','radiologist','pharmacist','accountant','front_desk']) {
  if (!migration.includes(`public.has_role(uid,'${role}')`)) {
    throw new Error(`clinical snapshot role authorization missing: ${role}`);
  }
}
if (!migration.includes("if _patient_id is null or not exists(select 1 from public.patients where id=_patient_id)")) {
  throw new Error('clinical snapshot patient existence guard missing');
}
if (!lock.includes('revoke execute on function public.get_patient_hub_clinical_snapshot(uuid) from public, anon;')) {
  throw new Error('clinical snapshot anon/public execute revocation missing');
}
if (!lock.includes('grant execute on function public.get_patient_hub_clinical_snapshot(uuid) to authenticated;')) {
  throw new Error('clinical snapshot authenticated execute grant missing');
}

console.log('Patient Hub clinical snapshot authorization contract passed');
