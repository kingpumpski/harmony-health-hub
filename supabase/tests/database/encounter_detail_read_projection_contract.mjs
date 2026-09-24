import fs from 'node:fs';

const content = fs.readFileSync('src/pages/Encounters.tsx', 'utf8');
const checks = [
  'supabase.from("diagnoses").select("id, encounter_id, diagnosis, is_principal")',
  '.from("prescriptions")\n        .select("id, encounter_id, medication, dosage, frequency, duration, status")',
];
for (const projection of checks) {
  if (!content.includes(projection)) throw new Error(`Expected encounter projection missing: ${projection}`);
}
if (content.includes('supabase.from("diagnoses").select("*")')) throw new Error('Broad diagnosis read remains');
if (content.includes('.from("prescriptions")\n        .select("*")')) throw new Error('Broad prescription read remains');
console.log('Encounter detail read projection contract passed');
