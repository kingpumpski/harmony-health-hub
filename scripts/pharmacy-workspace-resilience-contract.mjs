import assert from 'node:assert/strict';
import fs from 'node:fs';

const source = fs.readFileSync('src/pages/Pharmacy.tsx', 'utf8');
const packageJson = JSON.parse(fs.readFileSync('package.json', 'utf8'));
const loaderStart = source.indexOf('const load = useCallback(async () => {');
const loaderEnd = source.indexOf('\n\n  useEffect(() => {', loaderStart);
assert.ok(loaderStart >= 0 && loaderEnd > loaderStart, 'pharmacy workspace loader must exist');
const loader = source.slice(loaderStart, loaderEnd);
assert.match(source, /const workspaceLoadGeneration = useRef\(0\)/, 'pharmacy workspace must track request generations');
assert.match(loader, /const request = \+\+workspaceLoadGeneration\.current/, 'each refresh must invalidate older requests');
assert.match(loader, /if \(request !== workspaceLoadGeneration\.current\) return;/, 'stale workspace responses must not update state');
assert.match(loader, /catch \(error\)/, 'thrown network failures must be handled');
assert.match(loader, /finally \{\s*if \(request === workspaceLoadGeneration\.current\) setLoading\(false\);/, 'only the current request may clear loading state');
assert.match(source, /workspaceLoadGeneration\.current \+= 1;\s*window\.clearInterval\(refreshTimer\);/, 'unmount must invalidate pending requests and clear the refresh timer');
assert.match(packageJson.scripts.test, /test:pharmacy-workspace-resilience/, 'resilience contract must be part of the required test chain');
assert.equal(packageJson.scripts['test:pharmacy-workspace-resilience'], 'node scripts/pharmacy-workspace-resilience-contract.mjs');
console.log('Pharmacy workspace resilience contract passed.');
