import fs from 'node:fs';

const cases = [
  ['src/pages/OutsideLabUploads.tsx', "select('id,patient_id,document_type,title,created_at,ai_analysis')"],
  ['src/pages/Telemedicine.tsx', "select('id,patient_id,practitioner_id,room_name,provider,scheduled_at,status,payment_required,payment_received,service_order_id')"],
  ['src/pages/TreatmentTemplates.tsx', "select('id,name,diagnosis,description,prescriptions,is_ai_generated,created_at')"],
];
for (const [file, projection] of cases) {
  const content = fs.readFileSync(file, 'utf8');
  if (!content.includes(projection)) throw new Error(`Expected explicit projection missing: ${file}`);
  if (content.includes(".select('*')")) throw new Error(`Broad select('*') remains in protected ancillary clinical surface: ${file}`);
}
console.log('Clinical ancillary read projection contract passed');
