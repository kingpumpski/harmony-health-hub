import fs from 'node:fs';

const migrationPath = 'supabase/migrations/20260916103000_nextgen_clinical_audit_convergence.sql';
const sql = fs.readFileSync(migrationPath, 'utf8');

const requiredTables = [
  'patients',
  'appointments',
  'encounters',
  'prescriptions',
  'medication_administrations',
  'lab_orders',
  'lab_results',
  'imaging_orders',
  'insurance_claims',
  'invoices',
  'payments',
  'admissions',
  'ward_beds',
  'nursing_care_plans',
  'nursing_shift_handovers',
  'emergency_cases',
  'theatre_cases',
  'transfusion_records',
];

if (!sql.includes('public.audit_clinical_record_change()')) {
  throw new Error('Canonical clinical audit function is not referenced');
}
if (!sql.includes('AFTER INSERT OR UPDATE OR DELETE')) {
  throw new Error('Clinical audit trigger must cover inserts, updates and deletes');
}
if (!sql.includes('DROP TRIGGER IF EXISTS')) {
  throw new Error('Audit convergence must replace an existing trigger deterministically');
}
for (const table of requiredTables) {
  if (!sql.includes(`'${table}'`)) throw new Error(`Audit convergence missing table: ${table}`);
}
if (!sql.includes("to_regclass('public.' || table_name) IS NOT NULL")) {
  throw new Error('Audit convergence must tolerate migration-order table availability');
}
if (!sql.includes("to_regprocedure('public.audit_clinical_record_change()') IS NOT NULL")) {
  throw new Error('Audit convergence must tolerate audit-function migration ordering');
}
if (sql.includes('CREATE TABLE') || sql.includes('CREATE FUNCTION public.audit_clinical_record_change')) {
  throw new Error('Audit convergence must not introduce a parallel audit subsystem');
}

console.log('Next-gen clinical audit convergence contract passed: canonical audit reuse, deterministic trigger replacement, inpatient continuity coverage, migration-order guards, and no parallel audit subsystem are present.');
