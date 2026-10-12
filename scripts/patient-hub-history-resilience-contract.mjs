import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const source = readFileSync(new URL('../src/pages/patients/PatientHub.tsx', import.meta.url), 'utf8');
const start = source.indexOf('const loadHistory = useCallback(async () => {');
const end = source.indexOf('}, [patientId, roleSet, canClinicalHistory, currentAdmissionId]);', start);
assert.ok(start >= 0 && end > start, 'Patient Hub history loader must remain defined');
const loader = source.slice(start, end);
assert.match(loader, /const request = \+\+historyLoadGeneration\.current/);
assert.match(loader, /if \(request !== historyLoadGeneration\.current\) return;/);
assert.match(loader, /try\s*\{/);
assert.match(loader, /catch \(error\)/);
assert.match(loader, /finally\s*\{\s*setHistoryLoading\(false\);/);
assert.match(loader, /setFailedSections\(\['appointments', 'clinical', 'invoices', 'admissions'\]\)/);
assert.match(loader, /setHistoryError\(message\)/);
assert.match(loader, /if \(request === historyLoadGeneration\.current\) setHistoryLoading\(false\)/);
assert.ok(source.includes('historyLoadGeneration.current += 1;'), 'Unmount must invalidate pending patient history requests');
assert.doesNotMatch(loader, /setHistoryLoading\(false\);\s*return;/);
console.log('Patient Hub history loader resilience contract passed.');
