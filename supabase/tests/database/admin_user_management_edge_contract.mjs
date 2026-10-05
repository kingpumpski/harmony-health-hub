import fs from 'node:fs';
import assert from 'node:assert/strict';

const edge = fs.readFileSync('supabase/functions/admin-create-user/index.ts','utf8');
const ui = fs.readFileSync('src/pages/admin/AdminUsers.tsx','utf8');

assert.match(edge, /service\.from\('system_audit_log'\)\.insert/);
assert.match(edge, /actor_id:\s*caller\.id/);
assert.equal(edge.includes("service.rpc('record_system_audit'"), false);
assert.doesNotMatch(edge, /service\.rpc\('record_system_audit'/);
assert.match(edge, /auth\.admin\.deleteUser\(user\.id\)/);
assert.match(edge, /await writeAdminAudit\(/);
assert.match(ui, /context\?\.clone\(\)\.json/);
assert.match(ui, /User creation failed/);
assert.match(ui, /Role update failed/);

assert.match(edge, /Only a System Superuser can assign platform administrator roles/);
assert.match(edge, /Target user is not an active member of your facility/);
assert.match(edge, /active facility context is required before creating facility users/);
assert.match(edge, /Only a System Superuser can create or assign another System Superuser/);
assert.match(edge, /const requestedRole = String\(body\?\.role/);
assert.match(edge, /requestedFacilityId/);
assert.match(edge, /platform_onboard_user_facility/);
assert.match(edge, /action: 'admin_create_user'/);
assert.ok(edge.indexOf("action: 'admin_create_user'") > edge.indexOf("action: 'platform_onboard_user_facility'"), 'Final user-created audit must occur after facility onboarding succeeds');
assert.match(edge, /active facility context is required before viewing facility users/);
assert.match(edge, /active facility context is required before editing facility users/);
assert.match(edge, /Facility user directory lookup failed/);
assert.match(edge, /callerRole !== 'system_superuser'/);
assert.match(edge, /callerRolesError/);
assert.match(edge, /find\(\(role\) => role === 'system_superuser'\)/);
assert.match(ui, /!\['admin','it_admin','system_superuser'\]\.includes/);

console.log('Admin user-management Edge audit/error contract passed');

assert.match(edge, /body\?\.action === 'update_profile'/);
assert.match(edge, /auth\.admin\.updateUserById\(userId/);
assert.match(edge, /admin_update_user_profile/);
assert.match(ui, /Profile correction failed/);
assert.match(ui, /action: 'update_profile'/);
console.log('Account correction contract passed');

assert.match(edge, /normalized\.includes\('invalid authentication'\)/);
assert.match(edge, /normalized\.includes\('already been registered'\)/);
assert.match(edge, /return json\(\{ error: message \}, status\)/);
console.log('Admin provisioning HTTP error classification contract passed');
