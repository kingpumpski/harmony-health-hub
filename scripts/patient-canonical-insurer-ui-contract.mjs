import fs from 'node:fs';

const patientHub = fs.readFileSync('src/pages/patients/PatientHub.tsx', 'utf8');
const healthApi = fs.readFileSync('src/lib/healthApi.ts', 'utf8');

const requiredPatientHub = [
  "canManageInsurance",
  "list_insurance_companies",
  "set_patient_insurance_company",
  "insurance_company_id",
  "Canonical insurance company",
  "No active canonical insurers are configured yet.",
];

const requiredHealthApi = [
  "insurance_company_id",
  "insurance_group_number",
  "insurance_expiry",
  "city: data.city",
  "genotype: data.genotype",
];

const missing = [
  ...requiredPatientHub.filter((item) => !patientHub.includes(item)).map((item) => `PatientHub: ${item}`),
  ...requiredHealthApi.filter((item) => !healthApi.includes(item)).map((item) => `healthApi: ${item}`),
];

if (missing.length) {
  console.error('Patient canonical insurer UI contract failed:', missing);
  process.exitCode = 1;
} else {
  console.log('Patient canonical insurer UI contract passed.');
}
