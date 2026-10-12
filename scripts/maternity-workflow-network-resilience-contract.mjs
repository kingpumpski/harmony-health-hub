import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const source = readFileSync(new URL('../src/pages/Maternity.tsx', import.meta.url), 'utf8');
const packageJson = JSON.parse(readFileSync(new URL('../package.json', import.meta.url), 'utf8'));

assert.match(source, /const load=async\(\)=>\{setLoading\(true\);try\{/, 'maternity workspace load must guard rejected requests');
assert.match(source, /finally\{setLoading\(false\)\}/, 'all clinical mutations and loading must release the busy state');
assert.match(source, /A network error prevented maternity records from loading/, 'workspace network errors must be surfaced');
assert.match(source, /Unable to load maternity observations/, 'observation load failures must be handled');
assert.match(source, /const createEpisode=async\(\)=>\{if\(loading\)return/, 'episode creation must prevent duplicate submissions');
assert.match(source, /const addObservation=async\(\)=>\{if\(loading\)return/, 'observation recording must prevent duplicate submissions');
assert.match(source, /Unable to record the observation/, 'observation mutation network errors must be surfaced');
assert.match(packageJson.scripts.test, /test:maternity-workflow-network-resilience/, 'contract must be part of the required test chain');
assert.equal(packageJson.scripts['test:maternity-workflow-network-resilience'], 'node scripts/maternity-workflow-network-resilience-contract.mjs');

console.log('Maternity workflow network resilience contract passed.');
