import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const source = readFileSync(new URL('../src/pages/CanteenMeals.tsx', import.meta.url), 'utf8');

assert.match(source, /const load = useCallback\(async \(\) => \{[\s\S]*?finally \{\s*setLoading\(false\)/, 'refresh lifecycle must always clear loading');
assert.match(source, /const loadOrders = useCallback\(async \(\) => \{[\s\S]*?catch \(error\)/, 'order loading must handle rejected network requests');
assert.match(source, /const saveMenu = async \(publish: boolean\) => \{[\s\S]*?finally \{\s*setSaving\(false\)/, 'menu saving must always clear saving state');
assert.match(source, /if \(fromTime && untilTime && fromTime >= untilTime\)/, 'invalid availability windows must be rejected');
assert.match(source, /const createPlan = async[\s\S]*?finally \{\s*setOrderAction\(''\)/, 'dietary plan action must recover after failures');
assert.match(source, /const markDelivered = async[\s\S]*?finally \{\s*setOrderAction\(''\)/, 'delivery action must recover after failures');
assert.match(source, /if \(orderAction\) return/, 'duplicate order mutations must be blocked');
assert.match(source, /A network error prevented updating delivery/, 'delivery network failures must be surfaced');

console.log('Canteen meal operations network resilience contract passed.');
