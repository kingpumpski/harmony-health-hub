import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const source = readFileSync(new URL('../src/pages/NursingHandover.tsx', import.meta.url), 'utf8');
const packageJson = JSON.parse(readFileSync(new URL('../package.json', import.meta.url), 'utf8'));

assert.match(source, /const\[loading,setLoading\]=useState\(false\)/, 'loading state used by RefreshButton must be declared');
assert.doesNotMatch(source, /useAuth\(\)/, 'component must not call an unimported useAuth hook');
assert.match(source, /const load=async\(\)=>\{setLoading\(true\);try\{/, 'workspace loading must enter a guarded async lifecycle');
assert.match(source, /finally\{setLoading\(false\)\}/, 'loading state must always clear after success or failure');
assert.match(source, /catch\(error\)\{toast\(\{title:'Unable to load handovers'/, 'transport failures must produce a controlled loading error');
assert.match(source, /finally\{setSaving\(false\)\}/, 'save state must always clear');
assert.match(source, /finally\{setAcknowledgingId\(''\)\}/, 'acknowledgement state must always clear');
assert.match(source, /disabled=\{saving\}/, 'duplicate handover submissions must be prevented while saving');
assert.match(source, /disabled=\{acknowledgingId === r\.id\}/, 'duplicate acknowledgements must be prevented while pending');
assert.match(packageJson.scripts.test, /test:nursing-handover-resilience/, 'regression contract must be part of the required npm test chain');
assert.equal(packageJson.scripts['test:nursing-handover-resilience'], 'node scripts/nursing-handover-resilience-contract.mjs');

console.log('Nursing handover runtime and network resilience contract passed.');
