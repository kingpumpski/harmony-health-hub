import assert from 'node:assert/strict';
import fs from 'node:fs';

const migrationPath = 'supabase/migrations/20261127101000_fix_canteen_patient_order_facility_scope.sql';
const sourcePath = 'supabase/migrations/20260929150000_canteen_dietary_operational_workspace.sql';
const migration = fs.readFileSync(migrationPath, 'utf8');
const historical = fs.readFileSync(sourcePath, 'utf8');

assert.match(historical, /CREATE OR REPLACE FUNCTION public\.get_canteen_active_patient_orders\(\)/);
assert.match(historical, /FROM public\.meal_orders mo[\s\S]*JOIN public\.patients p ON p\.id=mo\.patient_id/);
assert.doesNotMatch(historical, /mo\.facility_id\s*=\s*v_facility/, 'protected historical migration must remain unchanged');

assert.match(migration, /CREATE OR REPLACE FUNCTION public\.get_canteen_active_patient_orders\(\)/);
assert.match(migration, /v_platform_superuser := public\.has_role\(uid, 'system_superuser'\)/);
assert.match(migration, /v_facility := public\.current_user_facility_id\(\)/);
assert.match(migration, /IF NOT v_platform_superuser AND v_facility IS NULL THEN/);
assert.match(migration, /mo\.facility_id = v_facility/);
assert.match(migration, /p\.facility_id = v_facility/);
assert.match(migration, /mp\.facility_id = v_facility/);
assert.match(migration, /mp\.patient_id = p\.id/);
assert.match(migration, /d\.facility_id = v_facility AND e\.facility_id = v_facility/);
assert.match(migration, /AND \(mo\.meal_plan_id IS NULL OR mp\.id IS NOT NULL\)/);
assert.match(migration, /SET search_path = ''/);
assert.match(migration, /REVOKE ALL ON FUNCTION public\.get_canteen_active_patient_orders\(\) FROM PUBLIC, anon/);
assert.match(migration, /GRANT EXECUTE ON FUNCTION public\.get_canteen_active_patient_orders\(\) TO authenticated/);
assert.match(migration, /NOTIFY pgrst, 'reload schema'/);

console.log('Canteen patient-order facility repair contract passed: authenticated reads are facility-scoped, linked patient/plan lineage is checked, and only system_superuser bypasses facility selection.');
