import assert from 'node:assert/strict';
import fs from 'node:fs';

const migration = fs.readFileSync(
  'supabase/migrations/20261127102000_reconcile_clinical_module_foreign_keys.sql',
  'utf8',
);
const exceptions = JSON.parse(fs.readFileSync('scripts/module-relationship-exceptions.json', 'utf8'));

const required = [
  {
    table: 'emergency_cases',
    column: 'patient_id',
    target: 'patients',
    constraint: 'emergency_cases_patient_id_fkey',
    onDelete: 'SET NULL',
    index: 'idx_emergency_cases_patient_id_fk',
  },
  {
    table: 'transfusion_records',
    column: 'patient_id',
    target: 'patients',
    constraint: 'transfusion_records_patient_id_fkey',
    onDelete: 'RESTRICT',
    index: 'idx_transfusion_records_patient_id_fk',
  },
  {
    table: 'medication_administrations',
    column: 'prescription_id',
    target: 'prescriptions',
    constraint: 'medication_administrations_prescription_id_fkey',
    onDelete: 'SET NULL',
    index: 'idx_medication_administrations_prescription_id_fk',
  },
  {
    table: 'ward_beds',
    column: 'admission_id',
    target: 'admissions',
    constraint: 'ward_beds_admission_id_fkey',
    onDelete: 'RESTRICT',
    index: 'idx_ward_beds_admission_id_fk',
  },
];

for (const item of required) {
  const constraint = new RegExp(
    'ALTER TABLE public\\.' + item.table +
    '[\\s\\S]*?ADD CONSTRAINT ' + item.constraint +
    '[\\s\\S]*?FOREIGN KEY \\(' + item.column +
    '\\) REFERENCES public\\.' + item.target +
    '\\(id\\)\\s+ON DELETE ' + item.onDelete + '\\s+NOT VALID',
  );
  assert.match(migration, constraint, item.table + '.' + item.column + ' FK semantics');
  assert.match(migration, new RegExp('CREATE INDEX IF NOT EXISTS ' + item.index));
  assert.match(migration, new RegExp('ALTER TABLE public\\.' + item.table + ' VALIDATE CONSTRAINT ' + item.constraint));
  assert.match(migration, new RegExp('FROM public\\.' + item.table + '[\\s\\S]*?LEFT JOIN public\\.' + item.target));
  assert.match(migration, new RegExp('WHERE [a-z]\\.' + item.column + ' IS NOT NULL AND [a-z]\\.id IS NULL'));
  assert.ok(
    exceptions.exceptions.some((entry) =>
      entry.table === item.table &&
      entry.column === item.column &&
      entry.target === item.target &&
      entry.reviewRequired === true
    ),
    'missing documented baseline exception for ' + item.table + '.' + item.column,
  );
}

assert.match(migration, /RAISE EXCEPTION '[^']*orphan reference\(s\)/);
assert.match(migration, /NOTIFY pgrst, 'reload schema'/);
assert.match(migration, /BEGIN;[\s\S]*COMMIT;/);

console.log('Clinical module FK repair contract passed: four orphan-preflighted, validated relationships with explicit retention semantics and supporting indexes.');
