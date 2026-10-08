import fs from 'node:fs';
import assert from 'node:assert/strict';

const files = [
  "src/pages/PatientPortal.tsx",
  "src/pages/MedicalRecords.tsx",
  "src/pages/Appointments.tsx",
  "src/pages/Telemedicine.tsx",
  "src/pages/Billing.tsx",
  "src/pages/OutsideLabUploads.tsx",
  "src/pages/patients/PatientCareContinuity.tsx",
  "src/pages/patients/PatientHub.tsx",
  "src/pages/Encounters.tsx",
  "src/pages/CanteenMeals.tsx",
  "supabase/functions/ai-clinical-assist/index.ts"
];

for (const file of files) {
  const source = fs.readFileSync(file, 'utf8');
  assert.ok(!source.includes('{ get: true }'), file + ': patient/read RPCs must not force GET transport');
}

console.log('[stable-patient-read] Patient/read RPC call sites use standard POST transport.');
