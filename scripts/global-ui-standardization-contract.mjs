import fs from 'node:fs';
import path from 'node:path';

const root = process.cwd();
const files = [];
function walk(dir) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (['node_modules', '.git', 'dist'].includes(entry.name)) continue;
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(full);
    else if (/\.(tsx|ts)$/.test(entry.name) && full.includes(path.join(root, 'src'))) files.push(full);
  }
}
walk(path.join(root, 'src'));

const sharedRefresh = files.filter(f => fs.readFileSync(f, 'utf8').includes('RefreshButton'));
const legacyRefresh = files.filter(f => /\bRefresh Data\b|>\s*Refresh\s*<|>\s*Refresh Data\s*</.test(fs.readFileSync(f, 'utf8')));
const refreshCw = files.filter(f => fs.readFileSync(f, 'utf8').includes('RefreshCw'));
const requiredSharedConsumers = [
  'src/components/records/RecordList.tsx',
  'src/components/workflow/OperationalWorklistShell.tsx',
  'src/components/workflow/WorklistDataTable.tsx',
  'src/pages/Appointments.tsx',
  'src/pages/Telemedicine.tsx',
];
const missingSharedConsumers = requiredSharedConsumers.filter(file => {
  const full = path.join(root, file);
  return !fs.existsSync(full) || !fs.readFileSync(full, 'utf8').includes('RefreshButton') && !fs.readFileSync(full, 'utf8').includes('PageHeader');
});
const telemedicine = fs.readFileSync(path.join(root, 'src/pages/Telemedicine.tsx'), 'utf8');

if (!fs.existsSync(path.join(root, 'src/components/ui/RefreshButton.tsx'))) throw new Error('Shared RefreshButton is missing');
if (!fs.existsSync(path.join(root, 'src/components/layout/PageHeader.tsx'))) throw new Error('Shared PageHeader is missing');
if (legacyRefresh.length) throw new Error('Legacy text refresh controls remain: ' + legacyRefresh.map(f => path.relative(root, f)).join(', '));
if (missingSharedConsumers.length) throw new Error('Required shared UI consumers are missing: ' + missingSharedConsumers.join(', '));
if (/className="card-medical p-5 space-y-3 h-fit"[\s\S]*Schedule Session/.test(telemedicine)) throw new Error('Telemedicine scheduling form is still rendered inline.');
if (!telemedicine.includes('setShowScheduler(true)')) throw new Error('Telemedicine Add New action does not open the scheduler modal.');

console.log(JSON.stringify({ files: files.length, sharedRefresh: sharedRefresh.length, refreshCwReferences: refreshCw.length, legacyRefresh: legacyRefresh.length }));
