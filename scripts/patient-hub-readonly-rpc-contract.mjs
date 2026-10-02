import fs from 'node:fs';

const source = fs.readFileSync('src/pages/patients/PatientHub.tsx', 'utf8');
const required = [
  "db.rpc('get_patient_current_treatment_snapshot', { _patient_id: patientId, _admission_id: currentAdmissionId }, { get: true })",
  "db.rpc('get_patient_appointments', { _patient_id: patientId, _limit: 100 }, { get: true })",
  "db.rpc('get_patient_hub_clinical_snapshot', { _patient_id: patientId }, { get: true })",
  "db.rpc('get_patient_invoices', { _patient_id: patientId, _limit: 100 }, { get: true })",
  "db.rpc('get_patient_admission_history', { _patient_id: patientId }, { get: true })",
];
for (const call of required) {
  if (!source.includes(call)) throw new Error('Read-only Patient Hub RPC must use GET: ' + call);
}
console.log('Patient Hub read-only RPC HTTP-method contract passed');
