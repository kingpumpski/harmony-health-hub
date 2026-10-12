import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const source = readFileSync(new URL('../src/pages/Billing.tsx', import.meta.url), 'utf8');
for (const name of ['loadInpatientCount', 'loadBillingSummary', 'loadPatients', 'loadBillable']) {
  assert.match(source, new RegExp('const ' + name + ' = useCallback\\(async \\(\\) => \\{'));
}
const billableStart = source.indexOf('const loadBillable = useCallback(async () => {');
const billableEnd = source.indexOf('}, [canPrepareBill, from, patientId]);', billableStart);
const billable = source.slice(billableStart, billableEnd);
assert.match(billable, /try\\s*\\{/);
assert.match(billable, /catch \\(error\\)/);
assert.match(billable, /finally \\{\\s*setLoading\\(false\\);/);
assert.match(source, /useState<number \\| null>\\(null\\)/);
assert.match(source, /inpatientCount === null \\? '—' : String\\(inpatientCount\\)/);
console.log('Billing workspace loading resilience contract passed.');
