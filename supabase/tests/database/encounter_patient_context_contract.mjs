import fs from 'node:fs';

const source = fs.readFileSync(
  'supabase/migrations/20260914110000_encounter_lifecycle_integrity_hardening.sql',
  'utf8'
);

const required = [
  "SELECT patient_id, status INTO patient_id_value, encounter_status FROM public.encounters WHERE id = _encounter_id;",
  "IF patient_id_value IS NULL THEN RAISE EXCEPTION 'Encounter does not exist'; END IF;",
  "INSERT INTO public.prescriptions (encounter_id, patient_id, prescribed_by",
  "SELECT e.status INTO encounter_status",
  "JOIN public.diagnoses d ON d.encounter_id = e.id",
  "IF NOT EXISTS (SELECT 1 FROM public.diagnoses WHERE id = _diagnosis_id AND encounter_id = _encounter_id)",
  "Completed or cancelled encounters are read-only"
];

for (const fragment of required) {
  if (!source.includes(fragment)) {
    throw new Error(`Encounter lifecycle context/ownership guard missing: ${fragment}`);
  }
}

console.log('Encounter lifecycle patient-context contract passed');
