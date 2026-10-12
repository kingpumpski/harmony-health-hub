import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const source = readFileSync(new URL('../src/pages/AnestheticAssessment.tsx', import.meta.url), 'utf8');
const packageJson = JSON.parse(readFileSync(new URL('../package.json', import.meta.url), 'utf8'));

assert.match(source, /const \[loading, setLoading\] = useState\(false\)/, 'loading state must be declared');
assert.match(source, /const load = async \(\) => \{[\s\S]*?try \{[\s\S]*?finally \{\s*setLoading\(false\)/, 'worklist loading must always reset');
assert.match(source, /patientError \|\| recordError/, 'returned Supabase errors must be surfaced');
assert.match(source, /catch \(error\) \{[\s\S]*?Network error/, 'rejected network requests must be handled');
assert.match(source, /const submit = async[\s\S]*?try \{[\s\S]*?finally \{\s*setSaving\(false\)/, 'save state must reset on every outcome');
assert.match(source, /if \(saving \|\| !pid \|\| !user\?\.id\) return/, 'duplicate or invalid submissions must be blocked');
assert.match(source, /disabled=\{loading \|\| saving\}/, 'refresh must be disabled while busy');
assert.match(packageJson.scripts.test, /test:anesthetic-assessment-network-resilience/, 'contract must be part of the required test chain');
assert.equal(packageJson.scripts['test:anesthetic-assessment-network-resilience'], 'node scripts/anesthetic-assessment-network-resilience-contract.mjs');

console.log('Anesthetic assessment network resilience contract passed.');
