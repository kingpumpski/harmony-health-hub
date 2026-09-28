import fs from 'node:fs';
import assert from 'node:assert/strict';

const edge = fs.readFileSync('supabase/functions/admin-create-user/index.ts','utf8');
const ui = fs.readFileSync('src/pages/admin/AdminUsers.tsx','utf8');

assert.match(edge, /service\.from\('system_audit_log'\)\.insert/);
assert.match(edge, /actor_id:\s*caller\.id/);
assert.doesNotMatch(edge, /service\\.rpc\\(['"]record_system_audit/);
assert.doesNotMatch(edge, /service\.rpc\('record_system_audit'/);
assert.match(edge, /auth\.admin\.deleteUser\(user\.id\)/);
assert.match(edge, /await writeAdminAudit\(/);
assert.match(ui, /context\?\.clone\(\)\.json/);
assert.match(ui, /User creation failed/);
assert.match(ui, /Role update failed/);

console.log('Admin user-management Edge audit/error contract passed');
