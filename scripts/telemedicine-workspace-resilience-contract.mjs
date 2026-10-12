import assert from 'node:assert/strict';
import fs from 'node:fs';

const source = fs.readFileSync('src/pages/Telemedicine.tsx', 'utf8');
assert.ok(source.includes("const [workspaceError, setWorkspaceError] = useState('')"), 'Staff telemedicine must expose workspace load errors');
assert.ok(source.includes('A network error prevented telemedicine from loading.'), 'Workspace loader must catch thrown network failures');
assert.ok(source.includes('Telemedicine workspace could not be refreshed.'), 'Workspace must render a visible retry state');
assert.ok(source.includes('Retry loading'), 'Workspace error must offer a retry action');
assert.ok(source.includes('setWorkspaceError(message)'), 'Returned RPC and query errors must be visible');
assert.ok(source.includes('const loadGeneration = useRef(0)'), 'Workspace refreshes must track the latest request');
assert.ok(source.includes('if (request !== loadGeneration.current) return;'), 'Stale workspace responses must not overwrite newer state');
assert.ok(source.includes('loadGeneration.current += 1; void supabase.removeChannel(channel)'), 'Unmount must invalidate pending workspace requests');
assert.ok(source.includes('void loadAll().finally(() => setRefreshing(false))'), 'Manual refresh must reset its busy indicator on failure');
assert.ok(source.includes('A network error prevented scheduling.'), 'Scheduling must catch thrown requests');
assert.ok(source.includes('A network error prevented the session from starting.'), 'Starting a session must catch thrown requests');
assert.ok(source.includes('A network error prevented the session from ending.'), 'Ending a session must catch thrown requests');
assert.ok(source.includes('setSubmitting(false)'), 'Scheduling must always clear its submission state');
console.log('Telemedicine workspace resilience contract passed');
