import fs from 'node:fs';
import assert from 'node:assert/strict';

const read = (path) => fs.readFileSync(path, 'utf8');
const checks = [
  ['src/pages/EmergencyBoard.tsx', /const \[createOpen, setCreateOpen\] = useState\(false\)/, /createOpen \? <div[^]*role="dialog"/],
  ['src/pages/TheatreBoard.tsx', /const \[createOpen, setCreateOpen\] = useState\(false\)/, /createOpen \? <div[^]*role="dialog"/],
  ['src/pages/TransfusionBoard.tsx', /const \[createOpen, setCreateOpen\] = useState\(false\)/, /createOpen \? <div[^]*role="dialog"/],
  ['src/pages/AdmissionManagement.tsx', /const \[createOpen, setCreateOpen\] = useState\(false\)/, /createOpen && <div[^]*role="dialog"/],
  ['src/pages/MedicationAdministration.tsx', /const \[createOpen, setCreateOpen\] = useState\(false\)/, /createOpen&&<div[^]*role="dialog"/],
  ['src/pages/OutsideLabUploads.tsx', /const \[uploadOpen, setUploadOpen\] = useState\(false\)/, /uploadOpen && <div[^]*role="dialog"/],
  ['src/pages/TreatmentTemplates.tsx', /const \[createOpen, setCreateOpen\] = useState\(false\)/, /createOpen && <div[^]*role="dialog"/],
  ['src/pages/WardBedBoard.tsx', /const \[createWardOpen, setCreateWardOpen\] = useState\(false\)/, /createWardOpen && <div[^]*role="dialog"/],
  ['src/pages/WardBedBoard.tsx', /const \[bedEditorOpen, setBedEditorOpen\] = useState\(false\)/, /bedEditorOpen && <div[^]*role="dialog"/],
  ['src/pages/CanteenMeals.tsx', /const \[menuEditorOpen, setMenuEditorOpen\] = useState\(false\)/, /menuEditorOpen && <div[^]*role="dialog"/],
  ['src/pages/CanteenMeals.tsx', /const \[planEditorOpen, setPlanEditorOpen\] = useState\(false\)/, /planEditorOpen && <div[^]*role="dialog"/],
  ['src/pages/Pharmacy.tsx', /const \[inventoryFormOpen, setInventoryFormOpen\] = useState\(false\)/, /inventoryFormOpen && <form/],
  ['src/pages/Billing.tsx', /const \[additionalServiceOpen, setAdditionalServiceOpen\] = useState\(false\)/, /additionalServiceOpen && <div/],
];

for (const [path, closedByDefault, conditionalRender] of checks) {
  const source = read(path);
  assert.match(source, closedByDefault, `${path}: creation/editor form must start closed`);
  assert.match(source, conditionalRender, `${path}: form must be rendered only after its assigned action opens it`);
}

const patientHub = read('src/pages/patients/PatientHub.tsx');
assert.match(patientHub, /const \[editing, setEditing\] = useState\(false\)/, 'Patient profile editor must start closed');
assert.match(patientHub, /Edit patient details/, 'Patient profile must expose an explicit edit action');
assert.match(patientHub, /editing && canEdit \? <form/, 'Patient profile form must be hidden until edit is requested');
assert.doesNotMatch(patientHub, /<form onSubmit=\{save\} className="space-y-5">/, 'Patient profile form must not be rendered unconditionally');

const wardBoard = read('src/pages/WardBedBoard.tsx');
assert.doesNotMatch(wardBoard, /window\.prompt\(['"]Bed number/, 'Bed creation must use the explicit dialog, not a browser prompt');

console.log(`Dashboard creation-form visibility contract passed (${checks.length + 3} checks).`);
