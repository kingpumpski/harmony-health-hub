import fs from 'node:fs';
import assert from 'node:assert/strict';

const migration = fs.readFileSync('supabase/migrations/20260918210000_hms_runtime_governance_boundaries.sql', 'utf8');
const reports = fs.readFileSync('src/lib/reportsCenter.ts', 'utf8');

for (const token of [
  'hms_current_role_code',
  'hms_module_is_enabled',
  'hms_assert_module_enabled',
  'set_hms_facility_module',
  'UPDATE public.hms_module_catalog',
  'CASE WHEN optional THEN false ELSE true END',
]) assert.ok(migration.includes(token), `Missing governance token: ${token}`);

assert.match(migration, /REVOKE ALL ON FUNCTION public\\.hms_assert_module_enabled\\(uuid,text\\) FROM PUBLIC/);
assert.match(migration, /GRANT EXECUTE ON FUNCTION public\\.hms_assert_module_enabled\\(uuid,text\\) TO authenticated/);
assert.match(migration, /auth\\.uid\\(\\) IS NULL/);
assert.match(reports, /rpc\\('hms_assert_module_enabled'/);
assert.equal((reports.match(/rpc\\('hms_assert_module_enabled'/g) ?? []).length, 2);
console.log('next-gen governance boundary checks passed');