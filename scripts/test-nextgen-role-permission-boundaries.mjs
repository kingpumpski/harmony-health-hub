import fs from 'node:fs';
import assert from 'node:assert/strict';

const migration = fs.readFileSync('supabase/migrations/20260919070000_hms_role_permission_workflow_boundaries.sql', 'utf8');

for (const token of [
  'CREATE SCHEMA IF NOT EXISTS private',
  'hms_app_role_map',
  "('admin','super_admin')",
  "('practitioner','doctor')",
  "('lab_technician','lab_scientist')",
  "('accountant','billing_clerk')",
  'private.hms_authorize',
  'public.hms_has_permission',
  'public.hms_assert_permission',
  'public.set_hms_role_module_permission',
  'hms_module_is_enabled',
  "scope_code IN ('none','facility','department','user','global')",
  "role_code='super_admin'",
  "scope_code='global'",
  "PERFORM public.hms_assert_permission(v_facility,'data-import','write')",
  "PERFORM public.hms_assert_permission(v_facility,'data-import','approve')",
  'INSERT INTO public.patients',
  'Rollback requires an entity-specific compensating adapter',
]) {
  assert.ok(migration.includes(token), `Missing HMS permission boundary token: ${token}`);
}

assert.match(
  migration,
  /CREATE OR REPLACE FUNCTION private\.hms_authorize\([\s\S]*?SECURITY DEFINER[\s\S]*?SET search_path=''/
);
assert.match(
  migration,
  /CREATE OR REPLACE FUNCTION public\.hms_assert_permission\([\s\S]*?SECURITY INVOKER[\s\S]*?SET search_path=''/
);
assert.ok(!migration.includes('rollback_hms_import_batch(uuid,text)'), 'Rollback overload with caller-supplied reason must not be introduced');
assert.ok(
  migration.includes('REVOKE ALL ON FUNCTION public.hms_assert_permission(uuid,text,text) FROM PUBLIC,anon'),
  'Permission assertion RPC must not be publicly executable'
);
assert.ok(
  migration.includes('GRANT EXECUTE ON FUNCTION public.hms_assert_permission(uuid,text,text) TO authenticated'),
  'Authenticated workflow callers must be able to invoke the permission assertion'
);

console.log('Next-gen HMS role/permission boundary contract checks passed.');
