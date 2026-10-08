import fs from 'node:fs';

const source = fs.readFileSync('src/pages/Pharmacy.tsx', 'utf8');
const component = fs.readFileSync('src/components/workflow/ClinicalDataTable.tsx', 'utf8');

const iconImport = source.match(/^import\s+\{([^}]+)\}\s+from\s+['"]lucide-react['"];?$/m)?.[1] ?? '';
const usedPharmacyIcons = ['AlertTriangle', 'BellRing', 'CreditCard', 'Package', 'Pencil', 'Pill', 'RefreshCw', 'Search', 'Settings2'];
for (const icon of usedPharmacyIcons) {
  if (!iconImport.split(',').map((name) => name.trim()).includes(icon)) {
    throw new Error(`Pharmacy must import the ${icon} icon used by its runtime workspace.`);
  }
}
if (/^<RefreshButton\b/m.test(source)) {
  throw new Error('Pharmacy must not contain an orphaned refresh control outside its component.');
}

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
