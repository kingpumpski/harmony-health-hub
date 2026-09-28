import fs from 'node:fs';
import assert from 'node:assert/strict';

const migration = fs.readFileSync(
  'supabase/migrations/20260928152500_fix_patient_document_storage_column.sql',
  'utf8',
);

assert.ok(migration.includes('CREATE OR REPLACE FUNCTION public.create_patient_document'));
assert.ok(migration.includes('storage_path'));
assert.equal(migration.includes('patient_documents(patient_id,document_type,file_url'), false);
assert.ok(migration.includes("COALESCE(status,'active') <> 'inactive'"));
assert.ok(migration.includes('REVOKE ALL ON FUNCTION public.create_patient_document'));
assert.ok(migration.includes('GRANT EXECUTE ON FUNCTION public.create_patient_document'));
