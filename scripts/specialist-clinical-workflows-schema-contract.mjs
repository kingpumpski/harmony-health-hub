import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const roleMigration = readFileSync("supabase/migrations/20261013161848_add_specialist_app_roles.sql", "utf8");
const schemaMigration = readFileSync("supabase/migrations/20261013161853_specialist_clinical_workflows_schema.sql", "utf8");
const clinicalStaffMigration = readFileSync("supabase/migrations/20261013161858_reconcile_specialist_clinical_staff_helper.sql", "utf8");

for (const role of ["physiotherapist", "ophthalmologist", "dentist", "dietician"]) {
  assert.match(roleMigration, new RegExp("ADD VALUE IF NOT EXISTS '" + role + "'"));
}
assert.ok(!/BEGIN\s*;/i.test(roleMigration), "Enum values must be committed before use in the next migration");
for (const table of ["physio_assessments","physio_treatment_plans","ophthalmology_assessments","dental_assessments","dietary_assessments","dietary_meal_orders","specialist_review_sessions"]) {
  assert.match(schemaMigration, new RegExp("CREATE TABLE IF NOT EXISTS public\\." + table));
  assert.match(schemaMigration, new RegExp("'" + table + "'"));
  assert.match(schemaMigration, new RegExp("CREATE POLICY " + table + "_facility_access"));
}
for (const required of ["patient_id uuid NOT NULL REFERENCES public.patients(id)", "encounter_id uuid NOT NULL REFERENCES public.encounters(id)", "specialty_category text", "package_session_count integer", "is_session_package boolean"]) {
  assert.ok(schemaMigration.includes(required), "Missing required schema contract: " + required);
}
assert.match(schemaMigration, /ENABLE ROW LEVEL SECURITY/);
assert.match(schemaMigration, /facility_id = \(SELECT public\.current_user_facility_id\(\)\)/);
assert.match(schemaMigration, /WITH CHECK/);
assert.match(schemaMigration, /_clinical_read/);
assert.match(schemaMigration, /current_user_is_clinical_staff/);
for (const role of ["physiotherapist", "ophthalmologist", "dentist", "dietician"]) {
  assert.ok(clinicalStaffMigration.includes(role), "Clinical staff helper missing " + role);
}
assert.match(clinicalStaffMigration, /pg_get_functiondef/);
assert.match(clinicalStaffMigration, /RAISE EXCEPTION/);
console.log("Specialist schema contract passed.");
