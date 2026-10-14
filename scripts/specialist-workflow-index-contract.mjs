import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const migration = readFileSync(new URL('../supabase/migrations/20261014104232_index_specialist_workflow_foreign_keys.sql', import.meta.url), 'utf8');

const indexes = [
  ['idx_dental_assessments_created_by', 'dental_assessments', 'created_by'],
  ['idx_dental_assessments_patient_id', 'dental_assessments', 'patient_id'],
  ['idx_dietary_assessments_created_by', 'dietary_assessments', 'created_by'],
  ['idx_dietary_assessments_patient_id', 'dietary_assessments', 'patient_id'],
  ['idx_dietary_meal_orders_created_by', 'dietary_meal_orders', 'created_by'],
  ['idx_dietary_meal_orders_assessment_id', 'dietary_meal_orders', 'dietary_assessment_id'],
  ['idx_dietary_meal_orders_encounter_id', 'dietary_meal_orders', 'encounter_id'],
  ['idx_dietary_meal_orders_patient_id', 'dietary_meal_orders', 'patient_id'],
  ['idx_ophthalmology_assessments_created_by', 'ophthalmology_assessments', 'created_by'],
  ['idx_ophthalmology_assessments_patient_id', 'ophthalmology_assessments', 'patient_id'],
  ['idx_physio_assessments_created_by', 'physio_assessments', 'created_by'],
  ['idx_physio_assessments_patient_id', 'physio_assessments', 'patient_id'],
  ['idx_physio_treatment_plans_assessment_id', 'physio_treatment_plans', 'assessment_id'],
  ['idx_physio_treatment_plans_created_by', 'physio_treatment_plans', 'created_by'],
  ['idx_physio_treatment_plans_initial_encounter_id', 'physio_treatment_plans', 'initial_encounter_id'],
  ['idx_physio_treatment_plans_patient_id', 'physio_treatment_plans', 'patient_id'],
  ['idx_specialist_review_sessions_appointment_id', 'specialist_review_sessions', 'appointment_id'],
  ['idx_specialist_review_sessions_created_by', 'specialist_review_sessions', 'created_by'],
  ['idx_specialist_review_sessions_encounter_id', 'specialist_review_sessions', 'encounter_id'],
  ['idx_specialist_review_sessions_patient_id', 'specialist_review_sessions', 'patient_id'],
];

for (const [name, table, column] of indexes) {
  assert.match(migration, new RegExp('create index if not exists ' + name + '\\s+on public\\.' + table + '\\s*\\(' + column + '\\)', 'i'), name + ' must cover the reported foreign key');
}
assert.equal((migration.match(/CREATE INDEX IF NOT EXISTS/gi) ?? []).length, 20, 'all 20 uncovered specialist foreign keys must be indexed');
console.log('Specialist workflow foreign-key index contract passed (20 indexes).');
