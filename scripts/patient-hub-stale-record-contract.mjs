import fs from 'node:fs';
import assert from 'node:assert/strict';

const source = fs.readFileSync('src/pages/patients/PatientHub.tsx', 'utf8');
assert.match(source, /useMemo, useRef, useState/);
assert.match(source, /const patientLoadVersion = useRef\(0\); const historyLoadVersion = useRef\(0\);/);
assert.match(source, /const version = \+\+patientLoadVersion\.current/);
assert.match(source, /if \(version !== patientLoadVersion\.current\) return;/);
assert.match(source, /const version = \+\+historyLoadVersion\.current/);
assert.match(source, /if \(version !== historyLoadVersion\.current\) return;/);
assert.match(source, /setPatient\(null\); setRows\(\{\}\); setFailedSections\(\[\]\);/);
const historyBatch = source.indexOf('const settled = await Promise.allSettled(specs.map');
const guard = source.indexOf('if (version !== historyLoadVersion.current) return;', historyBatch);
const stateWrite = source.indexOf('setRows(nextRows)', historyBatch);
assert.ok(historyBatch >= 0 && guard > historyBatch && stateWrite > guard,
  'A stale history batch must be discarded before it updates patient record state.');
console.log('Patient Hub stale-record response contract passed.');
