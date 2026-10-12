import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const source = readFileSync(new URL('../src/pages/admin/Settings.tsx', import.meta.url), 'utf8');
const packageJson = JSON.parse(readFileSync(new URL('../package.json', import.meta.url), 'utf8'));
const start = source.indexOf(' async function load(){');
const end = source.indexOf(' async function switchActiveFacility()', start);

assert.ok(start >= 0 && end > start, 'system settings load function must remain present');
const load = source.slice(start, end);
assert.match(load, /setLoading\(true\)/, 'loading state must begin before workspace requests');
assert.match(load, /try\s*\{[\s\S]*Promise\.all\(/, 'workspace reads must run within guarded loading lifecycle');
assert.match(load, /if\(error\) throw new Error\(error\.message\)/, 'configuration query errors must be surfaced');
assert.match(load, /if\(contextResult\?\.error && canControlTestMode\) throw new Error\(contextResult\.error\.message\)/, 'super-admin facility-context errors must not be silently accepted');
assert.match(load, /catch\(error\)\s*\{[\s\S]*toast\.error\(/, 'transport rejections must show controlled feedback');
assert.match(load, /finally\s*\{\s*setLoading\(false\)/, 'loading must always reset on success or failure');
assert.match(source, /if\(loading\)return <div[^>]*>Loading system configuration…/, 'loading UI must remain bounded by the loading state');
assert.match(packageJson.scripts.test, /test:settings-load-resilience/, 'regression contract must run in required test chain');
assert.equal(packageJson.scripts['test:settings-load-resilience'], 'node scripts/settings-load-resilience-contract.mjs');

console.log('System settings load resilience contract passed.');
