import fs from 'node:fs';

const migration = fs.readFileSync(
  'supabase/migrations/20260924142000_harden_inpatient_bidirectional_link_integrity.sql',
  'utf8',
);

const required = [
  "CREATE OR REPLACE FUNCTION public.enforce_inpatient_link_consistency()",
  "TG_TABLE_NAME = 'admissions'",
  "TG_TABLE_NAME = 'encounters'",
  "TG_TABLE_NAME = 'ward_beds'",
  "Admission and encounter patient linkage is inconsistent",
  "Encounter and admission patient linkage is inconsistent",
  "Ward bed and admission patient linkage is inconsistent",
  "Occupied ward bed requires patient and admission linkage",
  "Non-occupied ward bed cannot retain patient or admission linkage",
  "admissions_inpatient_link_consistency_trg",
  "encounters_inpatient_link_consistency_trg",
  "ward_beds_inpatient_link_consistency_trg",
  "REVOKE ALL ON FUNCTION public.enforce_inpatient_link_consistency() FROM PUBLIC, anon, authenticated",
];

for (const fragment of required) {
  if (!migration.includes(fragment)) {
    throw new Error(`Missing inpatient link integrity fragment: ${fragment}`);
  }
}

if (!/BEFORE INSERT OR UPDATE OF patient_id, encounter_id\s*\nON public\.admissions/.test(migration)) {
  throw new Error('Admission integrity trigger does not cover patient/encounter changes');
}
if (!/BEFORE INSERT OR UPDATE OF patient_id, admission_id\s*\nON public\.encounters/.test(migration)) {
  throw new Error('Encounter integrity trigger does not cover patient/admission changes');
}
if (!/BEFORE INSERT OR UPDATE OF patient_id, admission_id, status\s*\nON public\.ward_beds/.test(migration)) {
  throw new Error('Ward-bed integrity trigger does not cover occupancy/link changes');
}

console.log('Inpatient bidirectional link integrity contract passed');
