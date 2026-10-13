import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const page = readFileSync('src/pages/SpecialistAssessments.tsx', 'utf8');
const app = readFileSync('src/App.tsx', 'utf8');
const dashboard = readFileSync('src/components/dashboard/DashboardLayout.tsx', 'utf8');
const schema = readFileSync('supabase/migrations/20261013161000_specialist_clinical_workflows_schema.sql', 'utf8');

const expected = [
  ['physiotherapy', 'physio_assessments', ['assessment_type', 'chief_complaint', 'pain_scale', 'treatment_plan', 'functional_goals', 'next_session_date']],
  ['ophthalmology', 'ophthalmology_assessments', ['visual_acuity_left', 'visual_acuity_right', 'intraocular_pressure', 'slit_lamp_findings', 'fundoscopy_findings', 'specialized_test_orders']],
  ['dental', 'dental_assessments', ['tooth_chart_system', 'tooth_chart_data', 'procedures_performed', 'pending_procedures']],
  ['dietetics', 'dietary_assessments', ['weight_kg', 'height_cm', 'bmi', 'dietary_recall', 'nutritional_diagnosis', 'meal_plan']]
];

for (const [specialty, table, fields] of expected) {
  assert.ok(page.includes(`'${specialty}'`), `Assessment page must support ${specialty}`);
  assert.ok(page.includes(table), `Assessment page must write to ${table}`);
  assert.ok(dashboard.includes(`/specialist-assessments?specialty=${specialty}`), `Dashboard must route ${specialty} to its form`);
  for (const field of fields) assert.ok(schema.includes(field), `Schema must include ${field}`);
}
assert.match(app, /path="\/specialist-assessments"/, 'Specialist assessment route must be registered');
assert.match(app, /RoleGuard allowedRoles=\{\["physiotherapist","ophthalmologist","dentist","dietician","admin","it_admin","system_superuser"\]\}/, 'Assessment route must be role-gated');
assert.match(page, /rpc\('current_user_facility_id'\)/, 'Form must obtain the active facility from the authenticated database context');
assert.match(page, /created_by: user\.id/, 'Form must attribute saved assessments to the signed-in user');
assert.match(page, /from\(config\.table\)\.insert\(payload\)/, 'Form must persist assessments through the Supabase client');
assert.match(page, /if \(insertError\) throw new Error/, 'Form must surface database write failures');
assert.match(page, /schemaProbe = await db\.from\(config\.table\)\.select\('id'\)\.limit\(1\)/, 'Form must verify the selected specialty schema before enabling save');
assert.match(page, /schema is not deployed in this environment yet/, 'Missing specialty schema must show a safe deployment-pending message');
assert.match(page, /setSchemaReady\(false\)/, 'Schema verification must fail closed when the workspace is reloaded');
assert.match(page, /!schemaReady/, 'Save action must remain disabled until schema verification succeeds');
assert.match(page, /isAdministrativeRole \? Object\.keys\(specialties\)/, 'Specialty selector must not let non-admin staff switch into another specialty');
assert.match(page, /patient_id: selectedEncounter\.patient_id, encounter_id: selectedEncounter\.id/, 'Assessment must be linked to the selected encounter and patient');
assert.match(page, /No billing, test order, medication or meal-service transaction was created/, 'UI must not misrepresent downstream integrations as completed');
assert.match(schema, /ENABLE ROW LEVEL SECURITY/i, 'Specialist table migration must enable RLS');
console.log('Specialist assessment-entry contract passed.');
