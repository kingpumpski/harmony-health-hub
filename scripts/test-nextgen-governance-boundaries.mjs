import fs from 'node:fs';
import assert from 'node:assert/strict';

const migration = fs.readFileSync('supabase/migrations/20260918210000_hms_runtime_governance_boundaries.sql', 'utf8');
const reports = fs.readFileSync('src/lib/reportsCenter.ts', 'utf8');
const adminUsers = fs.readFileSync('src/pages/admin/AdminUsers.tsx', 'utf8');
const roleAssignment = fs.readFileSync('supabase/migrations/20260918230000_hms_governed_user_role_assignment.sql', 'utf8');

for (const token of [
  'hms_current_role_code',
  'hms_module_is_enabled',
  'hms_assert_module_access',
  'set_hms_facility_module',
  'hms_has_module_permission',
  'SECURITY DEFINER',
  "public.has_role(_user_id,'admin'::public.app_role)",
  'hms_role_code_for_app_role',
  'hms_user_has_module_permission',
  'hms_assert_module_access',
  "has_facility_access(auth.uid(), _facility_id)",
  'UPDATE public.hms_module_catalog',
  'CASE WHEN optional THEN false ELSE true END',
  'hms_role_codes_for_user',
  'hms_user_can',
  'hms_assert_user_can',
]) assert.ok(migration.includes(token), `Missing governance token: ${token}`);

assert.match(migration, /REVOKE ALL ON FUNCTION public\\.hms_assert_module_access\\(uuid,text\\) FROM PUBLIC/);
assert.match(migration, /GRANT EXECUTE ON FUNCTION public\\.hms_assert_module_enabled\\(uuid,text\\) TO authenticated/);
assert.match(migration, /auth\\.uid\\(\\) IS NULL/);
assert.match(reports, /rpc\\('hms_assert_module_enabled'/);
assert.equal((reports.match(/rpc\\('hms_assert_module_enabled'/g) ?? []).length, 2);
assert.match(adminUsers, /rpc\\('set_hms_user_role'/);
assert.doesNotMatch(adminUsers, /from\('user_roles'\)\\.(delete|insert)/);
for (const token of ['set_hms_user_role','The final administrator cannot be demoted','public.app_role','REVOKE ALL ON FUNCTION public.set_hms_user_role']) assert.ok(roleAssignment.includes(token), `Missing role-governance control: ${token}`);
console.log('next-gen governance boundary checks passed');