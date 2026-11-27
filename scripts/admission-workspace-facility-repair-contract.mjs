import assert from 'node:assert/strict';
import fs from 'node:fs';

const historical = fs.readFileSync('supabase/migrations/20260929150000_operational_workspace_scope_hardening.sql', 'utf8');
const migration = fs.readFileSync('supabase/migrations/20261127101100_fix_admission_workspace_facility_scope.sql', 'utf8');

assert.match(historical, /CREATE OR REPLACE FUNCTION public\.get_admission_workspace\(_limit integer DEFAULT 200\)/);
assert.match(historical, /v_role='admin' OR v_facility IS NULL OR b\.facility_id IS NULL/);
assert.doesNotMatch(historical, /a\.facility_id\s*=\s*v_facility/, 'protected historical migration must remain unchanged');

assert.match(migration, /CREATE OR REPLACE FUNCTION public\.get_admission_workspace\(_limit integer DEFAULT 200\)/);
assert.match(migration, /v_platform_superuser := public\.has_role\(auth\.uid\(\), 'system_superuser'\)/);
assert.match(migration, /v_facility := public\.current_user_facility_id\(\)/);
assert.match(migration, /IF NOT v_platform_superuser AND v_facility IS NULL THEN/);
assert.match(migration, /a\.facility_id = v_facility/);
assert.match(migration, /p\.facility_id = v_facility/);
assert.match(migration, /b\.facility_id IS DISTINCT FROM v_facility/);
assert.match(migration, /w\.facility_id IS DISTINCT FROM v_facility/);
assert.doesNotMatch(migration, /v_facility IS NULL\s+OR\s+b\.facility_id IS NULL/);
assert.match(migration, /SET search_path = pg_catalog, public/);
assert.match(migration, /REVOKE ALL ON FUNCTION public\.get_admission_workspace\(integer\) FROM PUBLIC, anon/);
assert.match(migration, /GRANT EXECUTE ON FUNCTION public\.get_admission_workspace\(integer\) TO authenticated/);
assert.match(migration, /NOTIFY pgrst, 'reload schema'/);

console.log('Admission workspace facility repair contract passed: admissions, patients, linked beds and wards are facility-consistent; only system_superuser bypasses.');
