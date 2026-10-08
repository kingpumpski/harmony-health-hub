import fs from 'node:fs';

const imaging = fs.readFileSync('src/pages/Imaging.tsx', 'utf8');
const worklist = fs.readFileSync('src/components/workflow/WorklistDataTable.tsx', 'utf8');
const requiredImaging = [
  "import RefreshButton from '@/components/ui/RefreshButton';",
  "import WorklistDataTable, { type WorklistColumn, type WorklistFilter } from '@/components/workflow/WorklistDataTable';",
  "title='Active patient list'",
  "title='Completed order list'",
  'filters={activeFilters}',
  'filters={completedFilters}',
  'onRefresh={() => void load()}',
  'lastUpdated={lastUpdated}',
];
for (const marker of requiredImaging) if (!imaging.includes(marker)) throw new Error('Radiology worklist contract missing: ' + marker);
const refreshImports = (imaging.match(/import RefreshButton from '@\\/components\\/ui\\/RefreshButton';/g) ?? []).length;
if (refreshImports !== 1) throw new Error('Radiology page must contain exactly one shared RefreshButton import.');
if (!worklist.includes("import RefreshButton from '@/components/ui/RefreshButton';")) throw new Error('WorklistDataTable must use the shared RefreshButton.');
if (!worklist.includes('RefreshCw')) throw new Error('WorklistDataTable loading indicator import is missing.');
if (!worklist.includes('<RefreshButton onClick={onRefresh} loading={refreshing} label="Refresh worklist" />')) throw new Error('WorklistDataTable refresh action is not standardized.');
if (!worklist.includes('Apply filters')) throw new Error('WorklistDataTable filter panel is missing Apply filters action.');
console.log('Radiology worklist/filter contract passed.');
