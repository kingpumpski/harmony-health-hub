import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const migration = readFileSync(new URL('../supabase/migrations/20261013190000_repair_lab_result_attachments_schema.sql', import.meta.url), 'utf8');
const compatibilityMigration = readFileSync(new URL('../supabase/migrations/20261013200000_laboratory_api_schema_compatibility.sql', import.meta.url), 'utf8');
const attachmentReadHardening = readFileSync(new URL('../supabase/migrations/20261014120000_harden_lab_result_attachment_read_rpc.sql', import.meta.url), 'utf8');
const helper = readFileSync(new URL('../src/lib/labResultAttachments.ts', import.meta.url), 'utf8');
const labPage = readFileSync(new URL('../src/pages/Laboratory.tsx', import.meta.url), 'utf8');
const resultsPage = readFileSync(new URL('../src/pages/LaboratoryResults.tsx', import.meta.url), 'utf8');
const encountersPage = readFileSync(new URL('../src/pages/Encounters.tsx', import.meta.url), 'utf8');

assert.match(migration, /CREATE TABLE IF NOT EXISTS public\.lab_result_attachments/, 'repair migration must safely create the missing attachment table');
assert.match(migration, /ALTER TABLE public\.lab_result_attachments ENABLE ROW LEVEL SECURITY/, 'attachment metadata must remain protected by RLS');
assert.match(migration, /facility_id = \(SELECT public\.current_user_facility_id\(\)\)/, 'metadata reads and writes must stay facility scoped');
assert.match(migration, /so\.related_entity_id = coalesce\(lo\.parent_order_id, lo\.id\)/, 'panel attachments must verify the parent order billing release');
assert.match(migration, /NOTIFY pgrst, 'reload schema'/, 'migration must refresh the PostgREST schema cache');
assert.match(helper, /PGRST205/, 'client must identify PostgREST missing-table errors');
assert.match(helper, /20261013190000_repair_lab_result_attachments_schema\.sql/, 'client guidance must name the repair migration');
assert.match(compatibilityMigration, /CREATE OR REPLACE FUNCTION public\.get_lab_result_attachments\(_lab_order_ids uuid\[\]\)/, 'attachment reads must use a facility-scoped API function');
assert.match(attachmentReadHardening, /SET search_path = ''/, 'attachment read RPC must use a hardened search path');
assert.match(attachmentReadHardening, /public\.has_role\(uid, 'admin'\)[\s\S]*public\.has_role\(uid, 'it_admin'\)/, 'facility administrators must retain troubleshooting access within the selected facility');
assert.match(attachmentReadHardening, /cardinality\(_lab_order_ids\)[\s\S]*> 300/, 'attachment read RPC must bound bulk requests');
assert.match(attachmentReadHardening, /lo\.facility_id = a\.facility_id/, 'attachment reads must match attachment and order facilities');
assert.match(attachmentReadHardening, /lr\.lab_order_id = lo\.id[\s\S]*lr\.patient_id = lo\.patient_id[\s\S]*lr\.facility_id = lo\.facility_id/, 'linked results must match order, patient, and facility lineage');
assert.match(attachmentReadHardening, /LIMIT 1000/, 'attachment read RPC must bound returned metadata rows');
assert.match(attachmentReadHardening, /REVOKE ALL ON FUNCTION public\.get_lab_result_attachments\(uuid\[\]\) FROM PUBLIC, anon/, 'attachment RPC must not be executable by public or anonymous roles');
assert.match(compatibilityMigration, /CREATE OR REPLACE FUNCTION public\.get_laboratory_test_group\(_include_inactive boolean/, 'compatibility RPC must preserve the reported singular panel function name');
assert.match(compatibilityMigration, /JOIN public\.patients p ON p\.id=lo\.patient_id AND p\.facility_id=v_facility/, 'attachment reads must verify patient facility scope');
assert.match(compatibilityMigration, /so\.status IN \('released','in_progress','completed'\)/, 'attachment reads must require a released laboratory service order');
assert.match(helper, /laboratoryNetworkUnavailableMessage/, 'client must distinguish network failures from schema-cache failures');
assert.match(labPage, /isMissingLabResultAttachmentsTable/, 'laboratory workspace must handle an unapplied attachment schema');
assert.match(resultsPage, /isMissingLabResultAttachmentsTable/, 'clinician results must handle an unapplied attachment schema');
assert.match(encountersPage, /isMissingLaboratoryPanelFunction/, 'encounter ordering must tolerate a missing panel RPC without disabling individual tests');

console.log('Laboratory attachment schema repair contract passed.');
