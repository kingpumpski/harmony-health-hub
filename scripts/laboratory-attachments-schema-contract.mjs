import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const migration = readFileSync(new URL('../supabase/migrations/20261013190000_repair_lab_result_attachments_schema.sql', import.meta.url), 'utf8');
const helper = readFileSync(new URL('../src/lib/labResultAttachments.ts', import.meta.url), 'utf8');
const labPage = readFileSync(new URL('../src/pages/Laboratory.tsx', import.meta.url), 'utf8');
const resultsPage = readFileSync(new URL('../src/pages/LaboratoryResults.tsx', import.meta.url), 'utf8');

assert.match(migration, /CREATE TABLE IF NOT EXISTS public\.lab_result_attachments/, 'repair migration must safely create the missing attachment table');
assert.match(migration, /ALTER TABLE public\.lab_result_attachments ENABLE ROW LEVEL SECURITY/, 'attachment metadata must remain protected by RLS');
assert.match(migration, /facility_id = \(SELECT public\.current_user_facility_id\(\)\)/, 'metadata reads and writes must stay facility scoped');
assert.match(migration, /so\.related_entity_id = coalesce\(lo\.parent_order_id, lo\.id\)/, 'panel attachments must verify the parent order billing release');
assert.match(migration, /NOTIFY pgrst, 'reload schema'/, 'migration must refresh the PostgREST schema cache');
assert.match(helper, /PGRST205/, 'client must identify PostgREST missing-table errors');
assert.match(helper, /20261013190000_repair_lab_result_attachments_schema\.sql/, 'client guidance must name the repair migration');
assert.match(labPage, /isMissingLabResultAttachmentsTable/, 'laboratory workspace must handle an unapplied attachment schema');
assert.match(resultsPage, /isMissingLabResultAttachmentsTable/, 'clinician results must handle an unapplied attachment schema');

console.log('Laboratory attachment schema repair contract passed.');
