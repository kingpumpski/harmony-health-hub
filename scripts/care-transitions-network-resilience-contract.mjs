import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const source = readFileSync(new URL('../src/pages/CareTransitions.tsx', import.meta.url), 'utf8');
const packageJson = JSON.parse(readFileSync(new URL('../package.json', import.meta.url), 'utf8'));

assert.match(source, /\[loading,setLoading\]=useState\(false\)/, 'loading state must be declared');
assert.match(source, /const load=async\(\)=>\{setLoading\(true\);try\{/, 'all worklists must use a guarded loading lifecycle');
assert.match(source, /finally\{setLoading\(false\)\}/, 'loading state must always reset');
assert.match(source, /catch\(error\)\{toast\.error\(error instanceof Error\?error\.message:'A network error prevented care transitions from loading'\)\}/, 'transport failures must be surfaced');
assert.match(source, /const createReferral=async\(\)=>\{[\s\S]*?try\{[\s\S]*?finally\{setSaving\(false\)\}\};/, 'referral mutation must reset saving state on all outcomes');
assert.match(source, /const createTransition=async\(\)=>\{[\s\S]*?finally\{setSaving\(false\)\}/, 'transition mutations must reset saving state on all outcomes');
assert.match(source, /if\(saving\)return/, 'duplicate submissions must be guarded');
assert.match(source, /disabled=\{loading\}/, 'refresh action must be disabled while loading');
assert.match(packageJson.scripts.test, /test:care-transitions-network-resilience/, 'contract must run in required test chain');
assert.equal(packageJson.scripts['test:care-transitions-network-resilience'], 'node scripts/care-transitions-network-resilience-contract.mjs');

console.log('Care transitions network resilience contract passed.');
