import fs from 'node:fs';

const source = fs.readFileSync('src/pages/Pharmacy.tsx', 'utf8');
const component = fs.readFileSync('src/components/workflow/ClinicalDataTable.tsx', 'utf8');

if (!source.includes("import ClinicalDataTable, { ClinicalProgressBar, ClinicalStatusBadge, ClinicalTableAction } from '@/components/workflow/ClinicalDataTable';")) {
  throw new Error('Pharmacy must explicitly import every ClinicalDataTable component it renders.');
}
if (!component.includes('export function ClinicalProgressBar(')) {
  throw new Error('ClinicalProgressBar must remain an exported workflow component.');
}
if (!source.includes('<ClinicalProgressBar')) {
  throw new Error('Expected Pharmacy progress indicators to remain covered by the component contract.');
}

console.log('Pharmacy workspace component-import contract passed');
