import assert from 'node:assert/strict';
import fs from 'node:fs';

const read = (path) => fs.readFileSync(path, 'utf8');
const migration = read('supabase/migrations/20260928170000_clinical_reference_values.sql');
const coverageMigration = read('supabase/migrations/20260928183000_complete_triage_clinical_reference_coverage.sql');
const form = read('src/components/triage/TriageRecordForm.tsx');
const helper = read('src/lib/clinicalReferences.ts');
const admin = read('src/pages/admin/ClinicalReferences.tsx');
const app = read('src/App.tsx');
const permissions = read('src/lib/permissions.ts');
const sidebar = read('src/components/layout/Sidebar.tsx');

assert.match(migration, /source_name text NOT NULL/);
assert.match(migration, /source_url text NOT NULL/);
assert.match(migration, /source_url ~\* '\^https\?:\/\/'/);
assert.match(migration, /review_due_at timestamptz (?:GENERATED ALWAYS AS \(last_reviewed_at \+ interval '24 months'\) STORED|NOT NULL)/);
assert.match(migration, /ALTER TABLE public\.clinical_reference_values ENABLE ROW LEVEL SECURITY/);
assert.match(migration, /clinical_reference_admin_insert/);
assert.match(migration, /clinical_reference_admin_update/);

for (const parameter of [
  'blood_pressure_systolic',
  'blood_pressure_diastolic',
  'blood_pressure_combined',
  'body_temperature',
  'spo2',
  'heart_rate',
  'respiratory_rate',
  'pain_score',
  'weight_measurement',
  'height_measurement',
]) {
  assert.match(
    `${migration}\n${coverageMigration}`,
    new RegExp(`'${parameter}'`),
    `missing seeded reference: ${parameter}`,
  );
}

assert.match(helper, /clinical_reference_values/);
assert.match(form, /useClinicalReferences/);
assert.match(form, /aria-describedby/);
assert.doesNotMatch(form, /90–120 mmHg|60–80 mmHg|36\.1–37\.2 °C|95–100%|60–100 bpm/);
assert.match(form, /input\('weightKg'.*'weight_measurement'/);
assert.match(form, /input\('heightM'.*'height_measurement'/);\nassert.match(form, /'weight_measurement',\s*'height_measurement'/);
assert.match(coverageMigration, /World Health Organization \(WHO\)/);
assert.match(coverageMigration, /Body mass index \(BMI\) \/ Global Health Observatory/);
assert.match(coverageMigration, /normal_min, normal_max/);
assert.match(admin, /source_url/);
assert.match(admin, /reviewRequired/);
assert.match(app, /\/admin\/clinical-references/);
assert.match(permissions, /clinical_references/);
assert.match(sidebar, /Clinical References/);
console.log('Clinical reference contract checks passed.');
