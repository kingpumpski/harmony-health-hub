import assert from 'node:assert/strict';
import fs from 'node:fs';

const source = fs.readFileSync('src/pages/WardBedBoard.tsx', 'utf8');
assert.ok(source.includes('const [loadError, setLoadError] = useState(\'\')'), 'WardBedBoard must retain a visible load error');
assert.ok(source.includes('A network error prevented ward management from loading.'), 'WardBedBoard must handle rejected workspace requests');
assert.ok(source.includes('Ward workspace could not be refreshed.'), 'WardBedBoard must show a retryable workspace error');
assert.ok(source.includes('const loadGeneration = useRef(0)'), 'Ward workspace refreshes must track the latest request');
assert.ok(source.includes('if (request !== loadGeneration.current) return;'), 'Stale ward workspace responses must not overwrite newer state');
assert.ok(source.includes('loadGeneration.current += 1;'), 'Ward workspace must invalidate in-flight requests on unmount');
assert.ok(source.includes('const withBusy = async'), 'WardBedBoard mutations must share resilient busy-state handling');
assert.ok(source.includes('finally {\n      setBusy(false);\n    }'), 'Mutation busy state must always reset after thrown requests');
assert.ok(source.includes("withBusy('Transfer failed'"), 'Bed transfer must recover from thrown RPC requests');
assert.ok(source.includes("withBusy('Release failed'"), 'Bed release must recover from thrown RPC requests');
assert.ok(source.includes('loading={busy}') && !source.includes('loading={loading}'), 'Refresh action must use the declared busy state');
console.log('Ward and bed workspace network resilience contract passed');
