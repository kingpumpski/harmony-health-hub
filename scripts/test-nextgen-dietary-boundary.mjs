import fs from 'node:fs';
import assert from 'node:assert/strict';

const migrationDir = 'supabase/migrations';
const files = fs.readdirSync(migrationDir).filter((name) => /^202609.*\.sql$/.test(name)).sort();
const source = files.map((name) => fs.readFileSync(`${migrationDir}/${name}`, 'utf8')).join('\n');

for (const token of [
  'private.hms_user_has_dietary_facility_permission',
  "hms_has_permission(fm.facility_id, 'dietary-restaurant', lower(_action))",
  'DROP POLICY IF EXISTS "mp_staff_all"',
  'DROP POLICY IF EXISTS "mo_staff_all"',
  "private.hms_user_has_dietary_facility_permission('write')",
  "public.has_role(auth.uid(),'canteen'::public.app_role)",
]) {
  assert.ok(source.includes(token), `Missing dietary governance token: ${token}`);
}

assert.ok(source.includes("REVOKE ALL ON FUNCTION private.hms_user_has_dietary_facility_permission(text) FROM PUBLIC,anon"));
assert.ok(source.includes("GRANT EXECUTE ON FUNCTION private.hms_user_has_dietary_facility_permission(text) TO authenticated"));
console.log('Next-generation dietary authorization boundary contract passed.');
