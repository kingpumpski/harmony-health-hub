import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const source = readFileSync(new URL('../src/pages/Billing.tsx', import.meta.url), 'utf8');
for (const name of ['loadInpatientCount', 'loadBillingSummary', 'loadPatients', 'loadBillable']) {
  assert.ok(source.includes('const ' + name + ' = useCallback(async () => {'), name + ' callback must remain defined');
}
const billableStart = source.indexOf('const loadBillable = useCallback(async () => {');
const billableEnd = source.indexOf('}, [canPrepareBill, from, patientId]);', billableStart);
assert.ok(billableStart >= 0 && billableEnd > billableStart, 'billing-window loader must remain defined');
const billable = source.slice(billableStart, billableEnd);
assert.ok(billable.includes('try {'), 'billing-window loader catches unexpected request failures');
assert.ok(billable.includes('catch (error)'), 'billing-window loader handles unexpected request failures');
assert.ok(billable.includes('finally {') && billable.includes('setLoading(false);'), 'billing-window loader always clears loading');
assert.ok(source.includes('useState<number | null>(null)'), 'inpatient count starts unknown until successfully loaded');
assert.ok(source.includes("inpatientCount === null ? '—' : String(inpatientCount)"), 'failed inpatient queue does not display a false zero');
console.log('Billing workspace loading resilience contract passed.');
