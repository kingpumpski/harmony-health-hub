import fs from 'node:fs';
import assert from 'node:assert/strict';

const source = fs.readFileSync('src/pages/Laboratory.tsx', 'utf8');
const packageJson = JSON.parse(fs.readFileSync('package.json', 'utf8'));
const loader = source.slice(source.indexOf('const loadAll = useCallback(async'), source.indexOf('const counters = useMemo'));

assert.match(source, /import \{[^}]*\buseCallback\b[^}]*\} from 'react'/, 'Laboratory must import every React hook it uses; missing hook imports crash the lazy-loaded route at runtime');
assert.match(source, /const loadAll = useCallback\(async/, 'laboratory workspace refresh callback must be declared through the imported React hook');
assert.match(source, /const workspaceLoadGeneration = useRef\(0\)/, 'laboratory workspace must track request generations');
assert.match(loader, /const request = \+\+workspaceLoadGeneration\.current/, 'each refresh must invalidate older requests');
assert.match(loader, /if \(request !== workspaceLoadGeneration\.current\) return;/, 'stale workspace and specimen responses must not update state');
assert.match(loader, /if \(request === workspaceLoadGeneration\.current\) setLoading\(false\);/, 'stale requests must not clear the current loading state');
assert.match(loader, /if \(request === workspaceLoadGeneration\.current\) \{\s*toast\(/, 'stale request failures must not show obsolete errors');
assert.match(source, /workspaceLoadGeneration\.current \+= 1;\s*unsubscribe\(\);\s*window\.clearInterval\(refreshTimer\);/, 'unmount must invalidate requests and clean up refresh resources');
assert.match(packageJson.scripts.test, /test:laboratory-workspace-resilience/, 'laboratory workspace resilience contract must be part of the required test chain');
assert.equal(packageJson.scripts['test:laboratory-workspace-resilience'], 'node scripts/laboratory-workspace-resilience-contract.mjs');

console.log('Laboratory workspace resilience contract passed.');
