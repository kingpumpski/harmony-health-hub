import fs from 'node:fs';

const listSurfaces = [
  ['src/pages/PatientAudit.tsx', 'searchSlot'],
  ['src/pages/TreatmentTemplates.tsx', 'searchSlot'],
  ['src/pages/MedicalRecords.tsx', 'searchSlot'],
  ['src/pages/ReportsCenter.tsx', 'filterSlot'],
  ['src/pages/admin/AdminUsers.tsx', 'searchSlot'],
  ['src/pages/admin/PlatformFacilityOnboarding.tsx', 'searchSlot'],
];

for (const [file, marker] of listSurfaces) {
  const source = fs.readFileSync(file, 'utf8');
  if (!source.includes('<RecordList')) throw new Error(file + ' must use RecordList');
  if (!source.includes(marker)) throw new Error(file + ' must expose its list filters through the standardized RecordList filter panel');
}

const recordList = fs.readFileSync('src/components/records/RecordList.tsx', 'utf8');
for (const marker of ['Filter', 'Apply filters', 'role="search"', "RefreshButton"]) {
  if (!recordList.includes(marker)) throw new Error('RecordList filter standardization marker missing: ' + marker);
}

console.log('RecordList filter standardization contract passed');
