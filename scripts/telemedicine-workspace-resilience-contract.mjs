import assert from 'node:assert/strict';
import fs from 'node:fs';

const source = fs.readFileSync('src/pages/Telemedicine.tsx', 'utf8');
assert.ok(source.includes("const [workspaceError, setWorkspaceError] = useState('')"), 'Staff telemedicine must expose workspace load errors');
assert.ok(source.includes('A network error prevented telemedicine from loading.'), 'Workspace loader must catch thrown network failures');
assert.ok(source.includes('Telemedicine workspace could not be refreshed.'), 'Workspace must render a visible retry state');
assert.ok(source.includes('Retry loading'), 'Workspace error must offer a retry action');
assert.ok(source.includes('setWorkspaceError(message)'), 'Returned RPC and query errors must be visible');
assert.ok(source.includes('void loadAll().finally(() => setRefreshing(false))'), 'Manual refresh must reset its busy indicator on failure');
console.log('Telemedicine workspace resilience contract passed');
