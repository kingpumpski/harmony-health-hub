import fs from 'node:fs';

const source = fs.readFileSync('src/pages/patients/PatientHub.tsx', 'utf8');

for (const needle of [
  "function SectionUnavailable({ label, onRetry }",
  "The records have not been confirmed as empty. Retry to load this section.",
  "const [failedSections, setFailedSections] = useState<string[]>([]);",
  "setFailedSections(failed);",
  "failedSections.includes('appointments')",
  "failedSections.includes('clinical')",
  "failedSections.includes('invoices')",
  "failedSections.includes('admissions')",
  "db.rpc('get_patient_appointments', { _patient_id: patientId, _limit: 100 }, { get: true })"
]) {
  if (!source.includes(needle)) {
    throw new Error('Patient Hub section-load contract missing: ' + needle);
  }
}

if (!source.includes("setFailedSections(['clinical', 'admissions'])")) {
  throw new Error('Failed current-admission snapshot must mark dependent clinical sections unavailable');
}

console.log('Patient Hub section failure states and read-only appointment RPC contract passed');
