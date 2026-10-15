import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const catalogueMigration = readFileSync(new URL('../supabase/migrations/20261013170000_lab_paid_queue_reports_and_catalogue.sql', import.meta.url), 'utf8');
const panelMigration = readFileSync(new URL('../supabase/migrations/20261013180000_laboratory_test_panels.sql', import.meta.url), 'utf8');
const migration = readFileSync(new URL('../supabase/migrations/20261013190000_repair_lab_result_attachments_schema.sql', import.meta.url), 'utf8');
const compatibilityMigration = readFileSync(new URL('../supabase/migrations/20261013200000_laboratory_api_schema_compatibility.sql', import.meta.url), 'utf8');
const attachmentReadHardening = readFileSync(new URL('../supabase/migrations/20261014120000_harden_lab_result_attachment_read_rpc.sql', import.meta.url), 'utf8');
const missingObjectReconciliation = readFileSync(new URL('../supabase/migrations/20261015060000_reconcile_missing_laboratory_objects.sql', import.meta.url), 'utf8');
const attachmentColumnReconciliation = readFileSync(new URL('../supabase/migrations/20261015070000_reconcile_lab_result_attachment_columns.sql', import.meta.url), 'utf8');
const missingObjectDatabaseContract = readFileSync(new URL('../supabase/tests/database/laboratory_missing_objects_contract.sql', import.meta.url), 'utf8');
const migrationWorkflow = readFileSync(new URL('../.github/workflows/supabase-migrations.yml', import.meta.url), 'utf8');
const inpatientCompatibility = readFileSync(new URL('../supabase/migrations/20261014160000_inpatient_discharge_bill_legacy_rpc_compatibility.sql', import.meta.url), 'utf8');
const approvalReconciliation = readFileSync(new URL('../supabase/migrations/20261014170000_reassert_lab_result_approval_after_schema_reconciliation.sql', import.meta.url), 'utf8');
const inpatientPage = readFileSync(new URL('../src/pages/InpatientBilling.tsx', import.meta.url), 'utf8');
const helper = readFileSync(new URL('../src/lib/labResultAttachments.ts', import.meta.url), 'utf8');
const labPage = readFileSync(new URL('../src/pages/Laboratory.tsx', import.meta.url), 'utf8');
const resultsPage = readFileSync(new URL('../src/pages/LaboratoryResults.tsx', import.meta.url), 'utf8');
const encountersPage = readFileSync(new URL('../src/pages/Encounters.tsx', import.meta.url), 'utf8');

assert.match(panelMigration, /CREATE TABLE IF NOT EXISTS public\.lab_test_groups/, 'panel migration must create or reconcile the laboratory panel table');
assert.match(panelMigration, /facility_id uuid NOT NULL REFERENCES public\.healthcare_facilities\(id\)/, 'laboratory panels must reference the canonical healthcare_facilities table');
assert.doesNotMatch(panelMigration, /REFERENCES public\.facilities\(id\)/, 'panel migration must not reference the nonexistent legacy facilities table');
assert.match(panelMigration, /CREATE TABLE IF NOT EXISTS public\.lab_test_group_items/, 'panel migration must create or reconcile panel-to-test relationships');
assert.match(panelMigration, /ADD COLUMN IF NOT EXISTS group_id uuid REFERENCES public\.lab_test_groups\(id\)/, 'lab orders must support panel membership idempotently');
assert.match(panelMigration, /ADD COLUMN IF NOT EXISTS parent_order_id uuid REFERENCES public\.lab_orders\(id\)/, 'lab orders must support panel child-order lineage idempotently');
assert.match(panelMigration, /CREATE OR REPLACE FUNCTION public\.get_laboratory_test_groups/, 'panel migration must provide the frontend read RPC');
assert.match(panelMigration, /CREATE OR REPLACE FUNCTION public\.save_laboratory_test_group/, 'panel migration must provide the panel save RPC');
assert.match(panelMigration, /SET search_path = ''/, 'panel security-definer functions must pin an empty search path');

assert.match(migration, /CREATE TABLE IF NOT EXISTS public\.lab_result_attachments/, 'repair migration must safely create the missing attachment table');
assert.match(migration, /ALTER TABLE public\.lab_result_attachments ENABLE ROW LEVEL SECURITY/, 'attachment metadata must remain protected by RLS');
assert.match(migration, /facility_id = \(SELECT public\.current_user_facility_id\(\)\)/, 'metadata reads and writes must stay facility scoped');
assert.match(migration, /so\.related_entity_id = coalesce\(lo\.parent_order_id, lo\.id\)/, 'panel attachments must verify the parent order billing release');
assert.match(migration, /NOTIFY pgrst, 'reload schema'/, 'migration must refresh the PostgREST schema cache');
assert.match(helper, /PGRST205/, 'client must identify PostgREST missing-table errors');
assert.match(helper, /\(\(code === 'PGRST205' \|\| code === '42P01'\) && \/lab_result_attachments\/i\.test\(message \?\? ''\)\)/, 'missing-table codes must identify the attachment table instead of misclassifying unrelated database errors');
assert.match(helper, /20261013190000_repair_lab_result_attachments_schema\.sql/, 'client guidance must name the repair migration');
assert.match(compatibilityMigration, /CREATE OR REPLACE FUNCTION public\.get_lab_result_attachments\(_lab_order_ids uuid\[\]\)/, 'attachment reads must use a facility-scoped API function');
assert.match(attachmentReadHardening, /SET search_path = ''/, 'attachment read RPC must use a hardened search path');
assert.match(attachmentReadHardening, /public\.has_role\(uid, 'admin'\)[\s\S]*public\.has_role\(uid, 'it_admin'\)/, 'facility administrators must retain troubleshooting access within the selected facility');
assert.match(attachmentReadHardening, /cardinality\(_lab_order_ids\)[\s\S]*> 300/, 'attachment read RPC must bound bulk requests');
assert.match(attachmentReadHardening, /lo\.facility_id = a\.facility_id/, 'attachment reads must match attachment and order facilities');
assert.match(attachmentReadHardening, /lr\.lab_order_id = lo\.id[\s\S]*lr\.patient_id = lo\.patient_id[\s\S]*lr\.facility_id = lo\.facility_id/, 'linked results must match order, patient, and facility lineage');
assert.match(attachmentReadHardening, /LIMIT 1000/, 'attachment read RPC must bound returned metadata rows');
assert.match(attachmentReadHardening, /REVOKE ALL ON FUNCTION public\.get_lab_result_attachments\(uuid\[\]\) FROM PUBLIC, anon/, 'attachment RPC must not be executable by public or anonymous roles');
assert.match(missingObjectReconciliation, /CREATE TABLE IF NOT EXISTS public\.lab_test_groups/, 'reconciliation migration must restore missing laboratory panels idempotently');
assert.match(missingObjectReconciliation, /CREATE TABLE IF NOT EXISTS public\.lab_test_group_items/, 'reconciliation migration must restore panel membership idempotently');
assert.match(missingObjectReconciliation, /ADD COLUMN IF NOT EXISTS group_id uuid REFERENCES public\.lab_test_groups/, 'reconciliation migration must restore the panel group order field');
assert.match(missingObjectReconciliation, /ADD COLUMN IF NOT EXISTS parent_order_id uuid REFERENCES public\.lab_orders/, 'reconciliation migration must restore parent order lineage');
assert.match(missingObjectReconciliation, /ADD COLUMN IF NOT EXISTS sample_quantity text/, 'reconciliation migration must restore sample quantity');
assert.match(missingObjectReconciliation, /CREATE TABLE IF NOT EXISTS public\.lab_result_attachments/, 'reconciliation migration must restore the attachment metadata table');
assert.match(missingObjectReconciliation, /CREATE OR REPLACE FUNCTION public\.get_laboratory_test_groups\([\s\S]*_include_inactive boolean DEFAULT false/, 'reconciliation migration must restore the laboratory panel RPC');
assert.match(missingObjectReconciliation, /CREATE OR REPLACE FUNCTION public\.get_lab_result_attachments\(_lab_order_ids uuid\[\]\)/, 'reconciliation migration must restore the attachment RPC');
assert.match(missingObjectReconciliation, /REVOKE ALL ON FUNCTION public\.get_laboratory_test_groups\(boolean\) FROM PUBLIC, anon/, 'panel RPC must not be publicly or anonymously executable');
assert.match(missingObjectReconciliation, /REVOKE ALL ON FUNCTION public\.get_lab_result_attachments\(uuid\[\]\) FROM PUBLIC, anon/, 'attachment RPC must not be publicly or anonymously executable');
assert.match(missingObjectReconciliation, /NOTIFY pgrst, 'reload schema'/, 'reconciliation migration must refresh the PostgREST schema cache');
assert.match(attachmentColumnReconciliation, /ADD COLUMN IF NOT EXISTS lab_order_id uuid/, 'attachment reconciliation must restore missing attachment columns');
assert.match(attachmentColumnReconciliation, /Existing laboratory attachment ids contain nulls or duplicates/, 'attachment reconciliation must validate legacy primary-key values');
assert.match(attachmentColumnReconciliation, /Map existing values from verified source records/, 'attachment reconciliation must not invent missing legacy metadata');
assert.match(attachmentColumnReconciliation, /lr\.patient_id IS DISTINCT FROM lo\.patient_id[\s\S]*lr\.facility_id IS DISTINCT FROM lo\.facility_id/, 'attachment reconciliation must preserve result lineage');
assert.match(attachmentColumnReconciliation, /ENABLE ROW LEVEL SECURITY/, 'attachment reconciliation must preserve row-level security');
assert.match(attachmentColumnReconciliation, /NOTIFY pgrst, 'reload schema'/, 'attachment reconciliation must refresh the PostgREST schema cache');
assert.match(missingObjectDatabaseContract, /lab_result_attachments', 'storage_path'/, 'database contract must verify reconciled attachment fields');
assert.match(missingObjectDatabaseContract, /to_regprocedure\('public\.get_laboratory_test_groups\(boolean\)'\)/, 'database contract must verify the exact panel RPC signature');
assert.match(missingObjectDatabaseContract, /to_regprocedure\('public\.get_lab_result_attachments\(uuid\[\]\)'\)/, 'database contract must verify the exact attachment RPC signature');
assert.match(migrationWorkflow, /supabase test db --linked supabase\/tests\/database\/laboratory_missing_objects_contract\.sql/, 'production migration verification must run the laboratory missing-object contract');
assert.match(compatibilityMigration, /CREATE OR REPLACE FUNCTION public\.get_laboratory_test_group\(_include_inactive boolean/, 'compatibility RPC must preserve the reported singular panel function name');
assert.match(compatibilityMigration, /JOIN public\.patients p ON p\.id=lo\.patient_id AND p\.facility_id=v_facility/, 'attachment reads must verify patient facility scope');
assert.match(compatibilityMigration, /so\.status IN \('released','in_progress','completed'\)/, 'attachment reads must require a released laboratory service order');
assert.match(helper, /laboratoryNetworkUnavailableMessage/, 'client must distinguish network failures from schema-cache failures');
assert.ok(helper.includes('20261013180000_laboratory_test_panels.sql'), 'panel recovery guidance must identify the exact panel migration');
assert.ok(inpatientCompatibility.includes('_patient_id uuid,\n  _to timestamptz DEFAULT now()'), 'legacy inpatient clients must have a compatible two-argument RPC signature');
assert.ok(inpatientCompatibility.includes('public.get_inpatient_discharge_bill(_patient_id, v_admission_id, _to)'), 'legacy inpatient wrapper must delegate to the canonical facility-checked billing projection');
assert.ok(inpatientCompatibility.includes('REVOKE ALL ON FUNCTION public.get_inpatient_discharge_bill(uuid,timestamptz) FROM PUBLIC, anon'), 'legacy inpatient wrapper must not be publicly executable');
assert.match(inpatientPage, /isMissingInpatientDischargeBillFunction/, 'inpatient billing must provide actionable guidance for missing RPC errors');
assert.ok(helper.includes('20261014160000_inpatient_discharge_bill_legacy_rpc_compatibility.sql'), 'inpatient recovery guidance must name the compatibility migration');
assert.match(helper, /code === 'PGRST202' \|\| code === '404' \|\| status === 404\) && \/get_laboratory_test_groups\?/i, 'panel RPC errors must be classified by function name rather than any generic missing-RPC error');
assert.match(helper, /databaseFeatureUpdatingMessage[\s\S]*This feature is currently being updated\. Please try again later\./, 'missing RPCs must use a user-friendly temporary-unavailability message');
assert.match(encountersPage, /get_laboratory_test_groups RPC is unavailable/, 'encounter ordering must log the underlying missing panel RPC');
assert.match(labPage, /get_lab_result_attachments RPC is unavailable/, 'laboratory workspace must log the underlying missing attachment RPC');
assert.match(resultsPage, /get_lab_result_attachments RPC is unavailable/, 'clinician results must log the underlying missing attachment RPC');
assert.match(helper, /20261014120000_harden_lab_result_attachment_read_rpc\.sql/, 'attachment recovery guidance must include the latest RPC hardening migration');
assert.match(helper, /20261015060000_reconcile_missing_laboratory_objects\.sql/, 'client recovery guidance must identify the missing-object reconciliation migration');
assert.match(labPage, /isMissingLabResultAttachmentsTable/, 'laboratory workspace must handle an unapplied attachment schema');
assert.match(resultsPage, /isMissingLabResultAttachmentsTable/, 'clinician results must handle an unapplied attachment schema');
assert.match(encountersPage, /isMissingLaboratoryPanelFunction/, 'encounter ordering must tolerate a missing panel RPC without disabling individual tests');

// The 2026-10-13 pending panel migration replaces the newer approval function
// already recorded remotely. The final reconciliation migration must restore
// all authorization, patient/order/result/encounter lineage, billing release,
// and panel-aware notification safeguards after the older chain is applied.
assert.match(approvalReconciliation, /CREATE OR REPLACE FUNCTION public\.approve_lab_result\(_lab_result_id uuid\)/, 'reconciliation migration must restore the lab approval RPC');
assert.match(approvalReconciliation, /public\.has_role\(uid, 'system_superuser'::public\.app_role\)/, 'system superuser troubleshooting role must be preserved');
assert.match(approvalReconciliation, /r\.patient_id IS DISTINCT FROM o\.patient_id/, 'approval must enforce result/order patient lineage');
assert.match(approvalReconciliation, /v_patient_facility IS DISTINCT FROM o\.facility_id/, 'approval must enforce patient/order facility lineage');
assert.match(approvalReconciliation, /v_encounter_patient_id IS DISTINCT FROM o\.patient_id/, 'approval must enforce encounter patient lineage');
assert.match(approvalReconciliation, /v_encounter_facility_id IS DISTINCT FROM o\.facility_id/, 'approval must enforce encounter facility lineage');
assert.match(approvalReconciliation, /so\.related_entity_id = coalesce\(o\.parent_order_id, o\.id\)/, 'panel child result approval must verify billing against the parent order');
assert.match(approvalReconciliation, /so\.status IN \('released', 'in_progress', 'completed'\)/, 'approval must require a released billing service order');
assert.match(approvalReconciliation, /REVOKE ALL ON FUNCTION public\.approve_lab_result\(uuid\) FROM PUBLIC, anon/, 'approval RPC must not be publicly or anonymously executable');
assert.match(approvalReconciliation, /NOTIFY pgrst, 'reload schema'/, 'approval reconciliation must refresh the PostgREST schema cache');


assert.match(catalogueMigration, /ALTER COLUMN sample_quantity TYPE text[\s\S]*USING sample_quantity::text/, 'catalogue migration must reconcile legacy numeric sample_quantity types');
assert.match(catalogueMigration, /DROP POLICY IF EXISTS lab_result_attachments_facility_read/, 'catalogue migration must tolerate pre-existing attachment policies');
assert.match(panelMigration, /DO \$panel_legacy_preflight\$[\s\S]*Legacy lab_test_groups rows need verified facility/, 'panel reconciliation must fail closed for ambiguous populated legacy groups');
assert.match(panelMigration, /ADD COLUMN IF NOT EXISTS facility_id uuid[\s\S]*ADD COLUMN IF NOT EXISTS group_name text[\s\S]*ADD COLUMN IF NOT EXISTS group_code text/, 'panel reconciliation must add canonical columns to partially provisioned group tables');
assert.match(panelMigration, /DROP FUNCTION IF EXISTS public\.get_laboratory_test_groups\(boolean\)/, 'panel RPC migration must replace incompatible legacy return types safely');
assert.match(compatibilityMigration, /DROP FUNCTION IF EXISTS public\.get_lab_result_attachments\(uuid\[\]\)/, 'attachment RPC migration must replace incompatible legacy table return types safely');


assert.match(missingObjectDatabaseContract, /get_laboratory_test_groups\(boolean\).*return JSONB|must return JSONB/, 'database contract must verify the panel RPC JSON return type');
assert.match(missingObjectDatabaseContract, /get_lab_result_attachments\(uuid\[\]\).*return JSONB|must return JSONB/, 'database contract must verify the attachment RPC JSON return type');
assert.match(missingObjectDatabaseContract, /must not be executable by anon/, 'database contract must verify anonymous attachment RPC denial');
assert.match(missingObjectDatabaseContract, /panel groups must expose the canonical group name/, 'database contract must verify canonical panel columns');

console.log('Laboratory attachment schema repair contract passed.');
