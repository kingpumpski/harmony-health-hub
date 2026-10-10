import fs from 'node:fs';

const source = fs.readFileSync('src/pages/Telemedicine.tsx', 'utf8');
const query = "searchPatientDirectory('', 200).then(({ data, error }) => ({ data, error }))";
if (!source.includes(query)) {
  throw new Error('Telemedicine must preserve patient-directory errors when combining workspace loads');
}
if (source.includes("searchPatientDirectory('', 200).then(({ data }) => ({ data, error: null }))")) {
  throw new Error('Telemedicine must not convert patient-directory failures into successful empty results');
}
if (!source.includes('if (patientError || sessionError)')) {
  throw new Error('Telemedicine must surface patient-directory or session-loading failures');
}
console.log('Telemedicine patient-directory error propagation contract passed');
