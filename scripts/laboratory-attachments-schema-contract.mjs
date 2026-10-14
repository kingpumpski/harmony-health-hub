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

const metadataReadPolicy = migration.slice(
  migration.indexOf('CREATE POLICY lab_result_attachments_facility_read'),
  migration.indexOf('DROP POLICY IF EXISTS lab_result_attachments_technician_insert')
);
const metadataInsertPolicy = migration.slice(
  migration.indexOf('CREATE POLICY lab_result_attachments_technician_insert'),
  migration.indexOf('INSERT INTO storage.buckets')
);
assert.match(metadataReadPolicy, /so\.status IN \('released', 'in_progress', 'completed'\)/, 'direct metadata reads must enforce diagnostic payment release');
assert.match(metadataReadPolicy, /JOIN public\.patients p[\s\S]*p\.facility_id = lo\.facility_id/, 'direct metadata reads must validate patient facility lineage');
assert.ok(metadataReadPolicy.includes("storage_path LIKE lab_order_id::text || '/%'"), 'metadata paths must be bound to the referenced order');
assert.ok(metadataInsertPolicy.includes("storage_path LIKE lab_order_id::text || '/%'"), 'metadata inserts must not attach a different order’s storage object');

assert.match(labPage, /A thrown metadata request has an unknown commit outcome/, 'upload recovery must not delete an object when metadata commit outcome is unknown');
assert.match(labPage, /Could not open attachment/, 'laboratory attachment access must report thrown network failures');
assert.match(labPage, /Lab report attachments unavailable[\s\S]*attachmentRequestError instanceof Error/, 'attachment list network failures must not fail the entire laboratory workspace load');
assert.match(resultsPage, /Approved laboratory reports could not be refreshed/, 'approved-results loading must handle thrown RPC/network failures');
assert.match(resultsPage, /finally \{\s*setLoading\(false\);\s*\}/, 'approved-results loading state must always be released');
assert.match(helper, /PGRST205/, 'client must identify PostgREST missing-table errors');
assert.match(helper, /20261013190000_repair_lab_result_attachments_schema\.sql/, 'client guidance must name the repair migration');
assert.match(labPage, /isMissingLabResultAttachmentsApi/, 'laboratory workspace must handle missing attachment tables and RPCs');
assert.match(resultsPage, /isMissingLabResultAttachmentsTable/, 'clinician results must retain the backwards-compatible attachment error helper');


assert.match(migration, /REVOKE ALL ON TABLE public\.lab_result_attachments FROM PUBLIC, anon/, 'attachment metadata must not be readable by anonymous or public roles');
assert.match(migration, /GRANT SELECT, INSERT ON TABLE public\.lab_result_attachments TO authenticated/, 'metadata writes must be limited to authenticated sessions');
assert.match(migration, /file_size_bytes bigint NOT NULL CHECK \(file_size_bytes BETWEEN 1 AND 15728640\)/, 'attachment metadata must enforce the 15 MiB limit');
assert.match(migration, /mime_type text NOT NULL CHECK \(mime_type IN \('application\/pdf','image\/jpeg','image\/png'\)\)/, 'attachment metadata must restrict uploaded MIME types');
assert.match(migration, /uploaded_by = auth\.uid\(\)/, 'attachment metadata must be attributed to the authenticated uploader');
assert.match(migration, /lr\.patient_id = lo\.patient_id[\s\S]*lr\.facility_id = lo\.facility_id/, 'linked results must match order patient and facility');
assert.match(migration, /VALUES \([\s\S]*'lab-result-attachments',[\s\S]*false,[\s\S]*15728640/, 'attachment bucket must remain private and enforce the size limit');
assert.match(migration, /bucket_id = 'lab-result-attachments'[\s\S]*current_user_facility_id\(\)[\s\S]*current_user_is_clinical_staff\(\)/, 'storage reads must be limited to clinical staff in the active facility');
assert.match(migration, /so\.status IN \('released', 'in_progress', 'completed'\)/, 'storage access must require a released service order');
const attachmentRpc = readFileSync(new URL('../supabase/migrations/20261013200000_lab_result_attachment_read_rpc.sql', import.meta.url), 'utf8');
assert.match(attachmentRpc, /cardinality\(_lab_order_ids\)[\s\S]*> 300/, 'attachment read RPC must bound bulk requests');
assert.match(attachmentRpc, /REVOKE ALL ON FUNCTION public\.get_lab_result_attachments\(uuid\[\]\) FROM PUBLIC, anon/, 'attachment RPC must not be executable by public or anonymous roles');

console.log('Laboratory attachment schema repair contract passed.');
