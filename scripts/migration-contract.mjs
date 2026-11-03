import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
const root = process.cwd();
const trackedPaths = execFileSync('git', ['ls-files', '-z'], { encoding: 'utf8' }).split(String.fromCharCode(0)).filter(Boolean);
const forbiddenTrackedArtifacts = trackedPaths.filter((p) =>
  p.startsWith('supabase/.temp/') ||
  p.startsWith('.reconciliation/') ||
  p === 'database-reconciliation-evidence.zip' ||
  p === 'supabase/migrations/$(path)'
);
assert.deepEqual(
  forbiddenTrackedArtifacts,
  [],
  'Local Supabase state and reconciliation evidence archives must never be committed: ' + forbiddenTrackedArtifacts.join(', '),
);
const dir = path.join(root, 'supabase', 'migrations');
const sqlFiles = fs.readdirSync(dir).filter((n) => n.endsWith('.sql')).sort();
for (const name of sqlFiles) assert.match(name, /^\d{14}_.+\.sql$/, `Invalid migration filename (expected <14-digit-version>_<name>.sql): ${name}`);
const files = sqlFiles;
const versions = new Map();
const duplicateVersions = [];
for (const name of files) {
  const version = name.slice(0, 14);
  const previous = versions.get(version);
  if (previous) duplicateVersions.push(`${version}: ${previous} and ${name}`);
  else versions.set(version, name);
}
assert.deepEqual(duplicateVersions, [], 'Duplicate Supabase migration versions: ' + duplicateVersions.join('; '));
const migrations = files.map((name) => ({name, source: fs.readFileSync(path.join(dir,name),'utf8')}));
const all = migrations.map((m) => m.source).join('\n');
const read = (p) => fs.readFileSync(path.join(root,p),'utf8');
const must = (s,r,m) => assert.match(s,r,m);
for (const [table, columns] of Object.entries({
  lab_test_groups:['facility_id','group_name','group_code','is_active'],
  lab_test_group_items:['group_id','test_id','display_order'],
  lab_result_attachments:['lab_order_id','lab_result_id','facility_id','storage_path','uploaded_by'],
  lab_orders:['group_id','parent_order_id'],
  lab_test_catalogue:['sample_quantity'],
})) {
  must(all,new RegExp('CREATE TABLE(?: IF NOT EXISTS)? public\\.'+table+'\\b|ALTER TABLE public\\.'+table+'\\b','i'),'Migration chain must define/reconcile public.'+table);
  for (const c of columns) must(all,new RegExp('\\b'+c+'\\b','i'),'Required column missing from migration source: '+table+'.'+c);
}
for (const [idx,table] of [['lab_test_groups_facility_code_uidx','lab_test_groups'],['lab_orders_panel_child_test_uidx','lab_orders'],['lab_result_attachments_storage_path_key','lab_result_attachments']]) {
  if (idx === 'lab_result_attachments_storage_path_key') { must(all,/storage_path text NOT NULL UNIQUE/i,'Attachment storage_path must be unique'); } else { must(all,new RegExp('CREATE (?:UNIQUE )?INDEX(?: IF NOT EXISTS)?\\s+'+idx+'\\s+ON public\\.'+table,'i'),'Required index missing: '+idx); }
}
must(all,/CREATE OR REPLACE FUNCTION public\.get_laboratory_test_groups\([^)]*\)[\s\S]*?RETURNS\s+jsonb[\s\S]*?SECURITY DEFINER[\s\S]*?SET search_path\s*=/i,'panel RPC must pin search_path and return jsonb');
must(all,/CREATE OR REPLACE FUNCTION public\.get_lab_result_attachments\([^)]*\)[\s\S]*?RETURNS\s+jsonb[\s\S]*?SECURITY DEFINER[\s\S]*?SET search_path\s*=/i,'attachment RPC must pin search_path and return jsonb');
const attachment = read('supabase/migrations/20261015060000_reconcile_missing_laboratory_objects.sql');
must(attachment,/SET\s+search_path\s*=\s*''/i,'sensitive attachment RPC must use an empty pinned search_path');
for (const [r,m] of [
  [/a\.facility_id = v_facility/,'attachment read must be facility-scoped'],
  [/JOIN public\.patients p[\s\S]*?p\.facility_id = lo\.facility_id/,'attachment read must verify patient/order facility lineage'],
  [/lr\.lab_order_id = lo\.id[\s\S]*?lr\.patient_id = lo\.patient_id[\s\S]*?lr\.facility_id = lo\.facility_id/,'attachment read must verify result/order/patient/facility lineage'],
  [/so\.related_entity_id = coalesce\(lo\.parent_order_id, lo\.id\)[\s\S]*?so\.status IN \('released', 'in_progress', 'completed'\)/,'attachment read must require parent-aware billing release'],
  [/REVOKE ALL ON FUNCTION public\.get_lab_result_attachments\(uuid\[\]\) FROM PUBLIC, anon/i,'attachment RPC must revoke PUBLIC and anon'],
  [/GRANT EXECUTE ON FUNCTION public\.get_lab_result_attachments\(uuid\[\]\) TO authenticated/i,'attachment RPC must grant only authenticated execution'],
]) must(attachment,r,m);
const clinicalBoundary = read('supabase/migrations/20260914024000_harden_authenticated_clinical_rpc_boundaries.sql');
for (const fnName of ['create_imaging_order_with_payment_gate','create_lab_order_with_payment_gate']) {
  const start = clinicalBoundary.indexOf('CREATE OR REPLACE FUNCTION public.' + fnName + '(');
  const end = start < 0 ? -1 : clinicalBoundary.indexOf('$function$;', start);
  const fnSource = start < 0 || end < 0 ? '' : clinicalBoundary.slice(start, end + '$function$;'.length);
  must(fnSource,/SECURITY DEFINER[\s\S]*?SET\s+search_path\s*=\s*['"]{2}/i,fnName+' must use an empty pinned search_path');
}
let checked=0;
for (const {name,source} of migrations) {
  // Split at each function declaration so a preceding function or comment cannot
  // cause the search_path assertion to inspect the wrong function body.
  const functionParts = source.split(/(?=CREATE(?: OR REPLACE)? FUNCTION public\.)/i);
  for (const part of functionParts) {
    if (!/^CREATE(?: OR REPLACE)? FUNCTION public\./i.test(part) || !/\bSECURITY DEFINER\b/i.test(part)) continue;
    const functionHeader = part.split(/\bAS\s+\$[A-Za-z_]*\$/i, 1)[0];
    must(functionHeader,/SET\s+search_path\s*(?:=|TO)\s*/i,name+': SECURITY DEFINER function must pin search_path');
    // Legacy migrations contain historical SECURITY DEFINER functions pinned to public.
    checked++;
  }
}
const referenceTablesMigration = '20260910215225_restore_missing_reference_tables.sql';
must(read('supabase/migrations/' + referenceTablesMigration),/CREATE TABLE IF NOT EXISTS public[.]audit_logs/i,'clean replay must restore audit log table');
must(read('supabase/migrations/' + referenceTablesMigration),/CREATE TABLE IF NOT EXISTS public[.]sync_queue/i,'clean replay must restore sync queue table');
must(read('supabase/migrations/' + referenceTablesMigration),/CREATE TABLE IF NOT EXISTS public[.]lab_tests/i,'clean replay must restore laboratory reference table');
for (const table of ['audit_logs','sync_queue','lab_tests']) {
  assert.ok(files.indexOf(referenceTablesMigration) >= 0 && files.indexOf(referenceTablesMigration) < files.indexOf('20260910215228_81137334-9a88-408e-b7f3-0993eb7b9918.sql'), table+' must exist before historical RLS hardening references it');
}
const symptomMapMigration = '20260910215226_reconcile_ai_symptom_icd_map.sql';
must(read('supabase/migrations/' + symptomMapMigration),/CREATE TABLE IF NOT EXISTS public[.]ai_symptom_icd_map/i,'clean replay must restore the AI symptom/ICD map');
must(all,/CREATE TABLE IF NOT EXISTS public[.]ai_symptom_icd_map/i,'AI symptom/ICD map must be defined in the migration chain');
assert.ok(files.indexOf(symptomMapMigration) >= 0 && files.indexOf(symptomMapMigration) < files.indexOf('20260910215228_81137334-9a88-408e-b7f3-0993eb7b9918.sql'),'AI symptom/ICD map must exist before historical RLS hardening references it');
const diagnosisSuggestionsMigration = '20260910215227_reconcile_ai_diagnosis_suggestions.sql';
must(read('supabase/migrations/' + diagnosisSuggestionsMigration),/CREATE TABLE IF NOT EXISTS public[.]ai_diagnosis_suggestions/i,'clean replay must restore the AI diagnosis suggestions table');
must(all,/CREATE TABLE IF NOT EXISTS public[.]ai_diagnosis_suggestions/i,'AI diagnosis suggestions must be defined in the migration chain');
assert.ok(files.indexOf(diagnosisSuggestionsMigration) >= 0 && files.indexOf(diagnosisSuggestionsMigration) < files.indexOf('20260910215228_81137334-9a88-408e-b7f3-0993eb7b9918.sql'),'AI diagnosis suggestions must exist before historical RLS hardening references it');

const claimFinancialFoundation = read('supabase/migrations/20260912035000_global_hims_operational_integrity.sql');
const claimFinancialFoundationFunction = claimFinancialFoundation.match(/CREATE OR REPLACE FUNCTION public\.update_insurance_claim_financials\([\s\S]*?\$claim_financials\$;/i)?.[0] ?? '';
assert.ok(claimFinancialFoundationFunction,'early claim financial RPC must remain defined');
must(claimFinancialFoundationFunction,/\) RETURNS public\.insurance_claims/i,'early claim financial RPC must use the production insurance_claims row return type');
must(claimFinancialFoundationFunction,/UPDATE public\.insurance_claims[\s\S]*?RETURNING \* INTO c;[\s\S]*?RETURN c;/i,'early claim financial RPC must return the updated insurance_claims row');
assert.doesNotMatch(claimFinancialFoundationFunction,/RETURNS JSONB/i,'early claim financial RPC must not use the incompatible JSONB return type');
const theatreAnesthetistFunction = claimFinancialFoundation.match(/CREATE OR REPLACE FUNCTION public\.assign_theatre_anesthetist\([\s\S]*?END; \$assign_theatre_anesthetist\$;/i)?.[0] ?? '';
assert.ok(theatreAnesthetistFunction,'theatre anesthetist assignment RPC must remain defined');
must(theatreAnesthetistFunction,/\) RETURNS JSONB/i,'theatre anesthetist assignment RPC must preserve its JSONB return contract');
const claimFinancialBounds = read('supabase/migrations/20260920062000_insurance_claim_financial_bounds.sql');
const claimFinancialBoundsFunction = claimFinancialBounds.match(/CREATE OR REPLACE FUNCTION public\.update_insurance_claim_financials\([\s\S]*?\$claim_financials\$/i)?.[0] ?? '';
assert.ok(claimFinancialBoundsFunction,'claim financial bounds RPC must remain defined');
must(claimFinancialBoundsFunction,/\) RETURNS public\.insurance_claims/i,'claim financial bounds migration must preserve the production insurance_claims row return type');
assert.ok(files.indexOf('20260912035000_global_hims_operational_integrity.sql') < files.indexOf('20260920062000_insurance_claim_financial_bounds.sql'),'claim financial RPC foundation must precede its bounds hardening migration');
const claimTransitionMigration = read('supabase/migrations/20260920063000_insurance_claim_transition_state_hardening.sql');
must(claimTransitionMigration,/CREATE OR REPLACE FUNCTION public\.transition_insurance_claim_canonical\([\s\S]*?\)\s*RETURNS\s+JSON\b/i,'claim transition hardening must preserve the production JSON RPC return type');
const legacyClaimTransitionMigration = read('supabase/migrations/20260912027000_global_hims_workflow_reconciliation.sql');
const legacyClaimTransitionFunction = legacyClaimTransitionMigration.match(/CREATE OR REPLACE FUNCTION public\.transition_insurance_claim\([\s\S]*?END; \$\$;/i)?.[0] ?? '';
assert.ok(legacyClaimTransitionFunction,'legacy insurance claim transition function must remain defined');
assert.match(legacyClaimTransitionFunction,/RETURNS\s+JSON\b/i,'legacy claim transition RPC must retain its JSON return type');
assert.doesNotMatch(legacyClaimTransitionFunction,/RETURNS\s+JSONB\b/i,'legacy claim transition RPC must not change its return type');
const productionAdvisorMigration = read('supabase/migrations/20261103090000_reconcile_production_schema_advisor_findings.sql');
for (const [indexName, tableName, columnName] of [
  ['idx_hr_employees_archived_by','hr_employees','archived_by'],
  ['idx_lab_result_attachments_uploaded_by','lab_result_attachments','uploaded_by'],
  ['idx_lab_test_group_items_test_id','lab_test_group_items','test_id'],
  ['idx_lab_test_groups_created_by','lab_test_groups','created_by'],
]) {
  must(productionAdvisorMigration,new RegExp('CREATE INDEX IF NOT EXISTS\\s+'+indexName+'\\s+ON public\\.'+tableName+'\\s*\\('+columnName+'\\)','i'),'production advisor migration must index '+tableName+'.'+columnName);
}
const reportSeedFoundation = read('supabase/migrations/20260913162000_harden_reports_center_seed_function.sql');
must(reportSeedFoundation,/CREATE OR REPLACE FUNCTION public\.seed_facility_reports\(_facility_id UUID\)\s+RETURNS VOID\b/i,'unreleased report seed foundation must use the canonical VOID return type');
must(reportSeedFoundation,/DROP FUNCTION IF EXISTS public\.seed_facility_reports\(UUID\);[\s\S]*?CREATE OR REPLACE FUNCTION public\.seed_facility_reports\(_facility_id UUID\)\s+RETURNS VOID\b/i,'report seed hardening must drop the earlier INTEGER signature before recreating the canonical VOID RPC');
assert.doesNotMatch(reportSeedFoundation,/GET DIAGNOSTICS|RETURN v_count/i,'VOID report seeding must not retain the obsolete row-count return contract');
const reportSeedMigration = read('supabase/migrations/20260920211000_privileged_admin_resource_scope_hardening.sql');
must(reportSeedMigration,/CREATE OR REPLACE FUNCTION public\.seed_facility_reports\(_facility_id uuid\)\s+RETURNS void\b/i,'facility report seeding must preserve its established VOID RPC return type');
const reportSeedTypeTransition = read('supabase/migrations/20260914010028_reports_center_production_reconciliation.sql');
must(reportSeedTypeTransition,/DROP FUNCTION IF EXISTS public\.seed_facility_reports\(UUID\);[\s\S]*?CREATE OR REPLACE FUNCTION public\.seed_facility_reports\(_facility_id uuid\)\s+RETURNS void\b/i,'facility report seed return-type transition must explicitly drop and recreate the earlier INTEGER signature');
must(reportSeedTypeTransition,/DROP FUNCTION IF EXISTS public\.recover_stale_report_run\(UUID, INTEGER\);[\s\S]*?CREATE OR REPLACE FUNCTION public\.recover_stale_report_run\(_run_id UUID,_stale_after_minutes INTEGER DEFAULT 30\) RETURNS public\.report_generation_runs/i,'stale report recovery RPC must explicitly replace the earlier BOOLEAN signature with the canonical composite return type');
must(reportSeedTypeTransition,/DROP FUNCTION IF EXISTS public\.upsert_report_submission_tracking\(UUID, UUID, DATE, DATE, DATE, JSONB\);[\s\S]*?CREATE OR REPLACE FUNCTION public\.upsert_report_submission_tracking\(_report_id UUID,_facility_id UUID,_period_start DATE,_period_end DATE,_due_date DATE,_data_snapshot JSONB DEFAULT '\{\}'::jsonb\) RETURNS public\.report_submissions/i,'report submission upsert RPC must explicitly replace the earlier INTEGER signature with the canonical composite return type');
must(reportSeedMigration,/INSERT INTO public\.facility_report_config[\s\S]*?ON CONFLICT\(facility_id,report_id\) DO NOTHING;/i,'facility report seeding must be idempotent for each facility/report pair');
must(reportSeedMigration,/IF v_user IS NULL OR NOT public\.has_role\(v_user,'admin'\) THEN/i,'facility report seeding must require an authenticated administrator');
must(reportSeedMigration,/IF NOT public\.has_facility_access\(v_user,_facility_id\) THEN/i,'facility report seeding must enforce facility-scoped authorization');
const legacy = read('supabase/migrations/20261015060000_reconcile_missing_laboratory_objects.sql');
for (const [r,m] of [
  [/CREATE TABLE IF NOT EXISTS public\.lab_test_groups/i,'legacy repair must tolerate existing panel table'],
  [/CREATE TABLE IF NOT EXISTS public\.lab_test_group_items/i,'legacy repair must tolerate existing membership table'],
  [/ADD COLUMN IF NOT EXISTS group_id/i,'legacy repair must tolerate existing lab_orders.group_id'],
  [/ADD COLUMN IF NOT EXISTS parent_order_id/i,'legacy repair must tolerate existing lab_orders.parent_order_id'],
  [/CREATE TABLE IF NOT EXISTS public\.lab_result_attachments/i,'legacy repair must tolerate existing attachment table'],
  [/CREATE OR REPLACE FUNCTION public\.get_lab_result_attachments\(_lab_order_ids uuid\[\]\)/i,'base migration must restore canonical attachment RPC'],
  [/SET search_path\s*=\s*''/i,'sensitive attachment RPC must use an empty pinned search_path'],
  [/REVOKE ALL ON FUNCTION public\.get_lab_result_attachments\(uuid\[\]\) FROM PUBLIC, anon/i,'attachment RPC must revoke PUBLIC and anon'],
  [/GRANT EXECUTE ON FUNCTION public\.get_lab_result_attachments\(uuid\[\]\) TO authenticated/i,'attachment RPC must grant only authenticated execution'],
]) must(legacy,r,m);

const attachmentReconciliation = read('supabase/migrations/20261015070000_reconcile_lab_result_attachment_columns.sql');
for (const [r,m] of [
  [/ALTER TABLE public\.lab_result_attachments[\s\S]*?ADD COLUMN IF NOT EXISTS lab_order_id uuid/i,'legacy repair must reconcile missing attachment order linkage'],
  [/ALTER TABLE public\.lab_result_attachments[\s\S]*?ADD COLUMN IF NOT EXISTS lab_result_id uuid/i,'legacy repair must reconcile missing attachment result linkage'],
  [/ALTER TABLE public\.lab_result_attachments[\s\S]*?ADD COLUMN IF NOT EXISTS facility_id uuid/i,'legacy repair must reconcile missing attachment facility scope'],
  [/ALTER TABLE public\.lab_result_attachments[\s\S]*?ADD COLUMN IF NOT EXISTS storage_path text/i,'legacy repair must reconcile missing storage path metadata'],
  [/ALTER TABLE public\.lab_result_attachments[\s\S]*?ADD COLUMN IF NOT EXISTS file_size_bytes bigint/i,'legacy repair must reconcile missing attachment size metadata'],
  [/WHERE id IS NULL[\s\S]*?HAVING count\(\*\) > 1[\s\S]*?RAISE EXCEPTION/i,'legacy attachment identifiers must fail closed when null or duplicated'],
  [/ADD CONSTRAINT lab_result_attachments_pkey PRIMARY KEY \(id\)/i,'legacy attachment identifiers must have a primary key after validation'],
  [/v_missing IS NOT NULL[\s\S]*?RAISE EXCEPTION[\s\S]*?missing required metadata/i,'legacy attachment required metadata must fail closed rather than being guessed'],
  [/WHERE a\.facility_id IS DISTINCT FROM lo\.facility_id[\s\S]*?RAISE EXCEPTION/i,'legacy attachment facility scope must match its linked laboratory order'],
  [/file_size_bytes BETWEEN 1 AND 15728640/i,'attachment metadata writes must validate file size'],
  [/GROUP BY storage_path[\s\S]*?HAVING count\(\*\) > 1[\s\S]*?RAISE EXCEPTION/i,'ambiguous legacy storage paths must fail closed'],
  [/CREATE UNIQUE INDEX idx_lab_result_attachments_storage_path_unique[\s\S]*?ON public\.lab_result_attachments \(storage_path\)/i,'legacy storage paths must be unique when existing data allows it'],
]) must(attachmentReconciliation,r,m);

// Guard partial legacy schemas: missing audit tables are valid, and canonical
// tariff aliases must satisfy installations where service_tariffs.category is NOT NULL.
const medicationTransitionMigration = read('supabase/migrations/20260912173000_billing_pharmacy_marpayment_hardening.sql');
must(medicationTransitionMigration,/DROP FUNCTION IF EXISTS public\.transition_medication_administration\(UUID,TEXT,TEXT,TEXT,UUID\);[\s\S]*?CREATE OR REPLACE FUNCTION public\.transition_medication_administration\([\s\S]*?\)\s*RETURNS\s+JSONB/i,'MAR transition must explicitly replace the legacy UUID-returning function with the production JSONB RPC contract');
const medicationReopenCompositeMigration = read('supabase/migrations/20260912190000_module_workflow_reconciliation.sql');
must(medicationReopenCompositeMigration,/DROP FUNCTION IF EXISTS public\.reopen_medication_administration\(UUID,TEXT\);[\s\S]*?CREATE OR REPLACE FUNCTION public\.reopen_medication_administration\([\s\S]*?\)\s*RETURNS\s+public\.medication_administrations/i,'MAR reopen return-type transition must explicitly drop the preceding JSONB signature');
const medicationReopenBooleanMigration = read('supabase/migrations/20261001152932_harden_authenticated_clinical_mutation_boundaries.sql');
must(medicationReopenBooleanMigration,/DROP FUNCTION IF EXISTS public\.reopen_medication_administration\(UUID,TEXT\);[\s\S]*?CREATE OR REPLACE FUNCTION public\.reopen_medication_administration\([\s\S]*?\)\s*RETURNS\s+boolean/i,'MAR reopen must preserve the production BOOLEAN RPC contract');
const medicationAdministrationCompatibility = read('supabase/migrations/20260912022900_reconcile_medication_administration_legacy_columns.sql');
must(medicationAdministrationCompatibility,/ADD COLUMN IF NOT EXISTS scheduled_at TIMESTAMPTZ/i,'legacy medication administration must reconcile scheduled_at before indexing');
must(medicationAdministrationCompatibility,/ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ/i,'legacy medication administration must reconcile updated_at before trigger creation');
must(medicationAdministrationCompatibility,/DO \$medication_name_reconcile\$[\s\S]*?END;\s*\$medication_name_reconcile\$;/i,'medication-name reconciliation DO block must terminate correctly');
must(medicationAdministrationCompatibility,/DO \$medication_status_reconcile\$[\s\S]*?END;\s*\$medication_status_reconcile\$;/i,'medication-status reconciliation DO block must terminate correctly');
must(medicationAdministrationCompatibility,/DO \$medication_updated_at_reconcile\$[\s\S]*?END;\s*\$medication_updated_at_reconcile\$;/i,'medication-updated_at reconciliation DO block must terminate correctly');
assert.ok(files.indexOf('20260912022900_reconcile_medication_administration_legacy_columns.sql') < files.indexOf('20260912023000_global_medication_administration.sql'),'MAR legacy columns must be reconciled before MAR indexes and triggers');
const patientAuditFoundation = read('supabase/migrations/20260912001500_restore_patient_audit_log.sql');
must(patientAuditFoundation,/ADD CONSTRAINT patient_audit_log_action_check\s+CHECK/i,'legacy patient audit action values must remain constrained');
must(patientAuditFoundation,/conname\s*=\s*'patient_audit_log_action_check'/i,'legacy patient audit must check the exact action constraint name before adding it');
must(patientAuditFoundation,/pg_index[\s\S]*?indisunique[\s\S]*?indnatts = 1[\s\S]*?indkey\[0\]/i,'patient audit ID index must not duplicate an existing primary/unique index');
must(patientAuditFoundation,/END;\s*\$patient_audit_action_check\$;/i,'patient audit action-check DO block must terminate correctly');
must(patientAuditFoundation,/END;\s*\$patient_audit_id_unique\$;/i,'patient audit ID-index DO block must terminate correctly');
const patientAuditRetention = read('supabase/migrations/20260912002000_phase5_patient_audit_retention.sql');
must(patientAuditRetention,/IF to_regclass\('public\.patient_audit_log'\) IS NOT NULL THEN/i,'patient audit retention must guard absent legacy patient_audit_log tables');
must(patientAuditRetention,/ELSIF to_regclass\('public\.patient_audit'\) IS NOT NULL THEN/i,'patient audit retention must support the canonical patient_audit table');
const rlsPolicyConsolidation = read('supabase/migrations/20261103091000_consolidate_rls_policy_paths.sql');
must(rlsPolicyConsolidation,/END;\s*\$notification_tables\$;/i,'notification RLS policy consolidation DO block must terminate with END;');
must(rlsPolicyConsolidation,/uploaded_by = \(SELECT auth\.uid\(\)\)/i,'lab attachment insert policy must wrap auth.uid in a scalar subquery');
must(rlsPolicyConsolidation,/DROP POLICY IF EXISTS payroll_items_admin_it_accountant_select ON public\.payroll_items/i,'redundant payroll item SELECT policy must be removed without altering the ALL policy');
must(rlsPolicyConsolidation,/DROP POLICY IF EXISTS payroll_periods_admin_it_accountant_select ON public\.payroll_periods/i,'redundant payroll period SELECT policy must be removed without altering the ALL policy');
const reportSeedHardening = read('supabase/migrations/20260920211000_privileged_admin_resource_scope_hardening.sql');
must(reportSeedHardening,/CREATE OR REPLACE FUNCTION public\.seed_facility_reports\(_facility_id uuid\)\s+RETURNS void\b/i,'later reports seed hardening must preserve the production VOID contract');
assert.doesNotMatch(reportSeedHardening,/DROP FUNCTION IF EXISTS public\.seed_facility_reports\(UUID\)/i,'already-deployed report seed hardening migration must remain immutable');
const systemSettingsCatalogueMigration = read('supabase/migrations/20260912174000_system_settings_catalogues.sql');
assert.doesNotMatch(systemSettingsCatalogueMigration,/lab_test_catalogue/i,'system settings migration must not reference the lab catalogue before its foundation exists');
const labCatalogueFoundation = read('supabase/migrations/20260912200000_phase5_lab_catalogue_and_audit.sql');
must(labCatalogueFoundation,/CREATE TABLE IF NOT EXISTS public\.lab_test_catalogue/i,'Phase 5 must create the lab catalogue before applying its RLS policies');
const legacyLabCataloguePolicyCleanup = read('supabase/migrations/20260917073705_remove_legacy_lab_catalogue_policies.sql');
must(legacyLabCataloguePolicyCleanup,/DROP POLICY IF EXISTS "lab catalogue staff read" ON public\.lab_test_catalogue/i,'superseded broad lab catalogue read policy must be removed');
must(legacyLabCataloguePolicyCleanup,/DROP POLICY IF EXISTS "lab catalogue admin write" ON public\.lab_test_catalogue/i,'superseded lab-technician write policy must be removed');
assert.ok(files.indexOf('20260912200000_phase5_lab_catalogue_and_audit.sql') < files.indexOf('20260917073705_remove_legacy_lab_catalogue_policies.sql'),'lab catalogue policies must be cleaned only after the catalogue foundation exists');
const enterpriseRoles = read('supabase/migrations/20260912024500_global_hims_enterprise_operations.sql');
assert.doesNotMatch(enterpriseRoles,/public\.has_role\(auth\.uid\(\),\s*ARRAY\[/i,'HIMS policies must use the supported scalar has_role(uuid, app_role) signature');
const serviceTariffFoundation = read('supabase/migrations/20260912173000_billing_pharmacy_marpayment_hardening.sql');
const serviceTariffTable = serviceTariffFoundation.match(/CREATE TABLE IF NOT EXISTS public\.service_tariffs\s*\(([\s\S]*?)\n\);/i)?.[1] ?? '';
assert.ok(serviceTariffTable, 'service tariff foundation must define its table before aliases are seeded');
assert.doesNotMatch(serviceTariffTable,/^\s*category\s+TEXT\s+NOT NULL/im,'legacy category must remain nullable because canonical production schema does not contain that column');
const canonicalTariffs = read('supabase/migrations/20260919055127_reconcile_remaining_canonical_service_tariff_codes.sql');
must(canonicalTariffs,/INSERT INTO public\.service_tariffs\s*\(\s*service_code,\s*service_name,\s*department,\s*unit,\s*amount,\s*active,\s*currency,\s*metadata\s*\)/i,'canonical tariff aliases must use the production-compatible service_tariffs column set');
assert.doesNotMatch(canonicalTariffs,/amount\s*=\s*EXCLUDED\.amount/i,'canonical alias upserts must preserve facility-configured tariff amounts');
assert.doesNotMatch(canonicalTariffs,/\bcategory\b/i,'canonical tariff alias migration must not reference the legacy category column');
const medicationWorkflow = read('supabase/migrations/20260912190000_module_workflow_reconciliation.sql');
const medicationWorkflowTransition = medicationWorkflow.match(/CREATE OR REPLACE FUNCTION public\.transition_medication_administration\(([\s\S]*?)DROP FUNCTION IF EXISTS public\.reopen_medication_administration/i)?.[0] ?? '';
must(medicationWorkflowTransition,/RETURNS JSONB/i,'module workflow medication transition must preserve the JSONB RPC return contract');
must(medicationWorkflowTransition,/RETURN jsonb_build_object/i,'module workflow medication transition must return a JSONB response');
const medicationContext = read('supabase/migrations/20260923150000_medication_patient_context_hardening.sql');
const medicationContextTransition = medicationContext.match(/CREATE OR REPLACE FUNCTION public\.transition_medication_administration\(([\s\S]*?)REVOKE ALL ON FUNCTION public\.schedule_medication_administration/i)?.[0] ?? '';
must(medicationContextTransition,/RETURNS JSONB/i,'medication patient-context hardening must preserve the JSONB RPC return contract');
must(medicationContextTransition,/RETURN jsonb_build_object/i,'medication patient-context hardening must return a JSONB response');
const notificationSecurityMigration = read('supabase/migrations/20260912252000_production_security_reconciliation.sql');
must(notificationSecurityMigration,/DROP FUNCTION IF EXISTS public\.mark_notification_read\(UUID\);[\s\S]*?CREATE OR REPLACE FUNCTION public\.mark_notification_read\(_notification_id UUID\)\s+RETURNS BOOLEAN\b/i,'notification read RPC must explicitly transition from the earlier VOID signature to the production BOOLEAN return contract');
const patientHubEntrypoints = read("supabase/migrations/20260923130000_patient_hub_entrypoint_context_hardening.sql");
must(patientHubEntrypoints,/GRANT EXECUTE ON FUNCTION public\.record_patient_vitals\(UUID,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC\) TO authenticated/i,"patient vitals grant must match the nine-argument RPC signature");
const extendedFacilityInventory = read('supabase/migrations/20260930015100_extend_facility_reconciliation_inventory.sql');
const labInventoryBranch = extendedFacilityInventory.match(/union all select 'lab_results',[\s\S]*?(?=\nunion all select 'imaging_orders')/i)?.[0] ?? '';
must(labInventoryBranch,/r\.id,lo\.patient_id,[\s\S]*?from public\.lab_results r\s+left join public\.lab_orders lo on lo\.id=r\.lab_order_id/i,'lab-result facility inventory must derive patient identity through the parent lab order');
assert.doesNotMatch(labInventoryBranch,/\br\.patient_id\b/i,'lab-result facility inventory must not read the noncanonical lab_results.patient_id field');
const facility = read('supabase/migrations/20260930014000_clinical_facility_reconciliation_control_plane.sql');
const labResultBranch = facility.match(/elsif _entity_type='lab_results' then([\s\S]*?)elsif _entity_type='imaging_orders' then/i)?.[1] ?? '';
assert.ok(labResultBranch, 'clinical facility reconciliation must retain a lab_results branch');
assert.doesNotMatch(labResultBranch, /\br\.patient_id\b/i, 'lab_results reconciliation must not read patient_id from lab_results');
must(labResultBranch,/left join public\.lab_orders lo on lo\.id=r\.lab_order_id/i,'lab_results reconciliation must join the parent lab order');
must(labResultBranch,/\blo\.patient_id\b/i,'lab_results reconciliation must derive patient lineage through the parent lab order');
must(labResultBranch,/lr\.patient_id\s+IS NOT NULL\s+AND\s+lr\.patient_id\s+IS DISTINCT FROM\s+lo\.patient_id/i,'lab_results reconciliation must fail closed when legacy patient_id conflicts with the parent order');
// Diagnosis patient identity is canonicalized through encounters; the legacy nullable diagnoses.patient_id field is not authoritative and is absent from the clean-install schema.
const diagnosisFacilityBranch = facility.match(/elsif _entity_type='diagnoses' then([\s\S]*?)else raise exception 'Unsupported clinical entity type'/i)?.[1] ?? '';
must(diagnosisFacilityBranch,/join public\.encounters e on e\.id=d\.encounter_id/i,'facility reconciliation must resolve diagnosis patient identity through its encounter');
must(diagnosisFacilityBranch,/coalesce\(e\.facility_id,p\.facility_id\)/i,'diagnosis facility reconciliation must fall back through the encounter patient');
assert.doesNotMatch(diagnosisFacilityBranch,/\bd\.patient_id\b/i,'diagnosis reconciliation must not depend on the nullable legacy patient_id column');
const baseDiagnosisTrigger = read('supabase/migrations/20260930013000_canonical_clinical_facility_attribution.sql');
const baseDiagnosisTriggerBranch = baseDiagnosisTrigger.match(/elsif tg_table_name='diagnoses' then([\s\S]*?)\n  end if;/i)?.[1] ?? '';
must(baseDiagnosisTriggerBranch,/join public\.patients p on p\.id=e\.patient_id/i,'initial diagnosis facility trigger must derive the patient from the parent encounter');
assert.doesNotMatch(baseDiagnosisTriggerBranch,/new\.patient_id/i,'initial diagnosis facility trigger must not read NEW.patient_id');
const diagnosisRepairTrigger = read('supabase/migrations/20260930017100_repair_diagnosis_facility_workflow.sql');
const diagnosisRepairBranch = diagnosisRepairTrigger.match(/ELSIF tg_table_name='diagnoses' THEN([\s\S]*?)\n  END IF;/i)?.[1] ?? '';
must(diagnosisRepairBranch,/join public\.patients p on p\.id=e\.patient_id/i,'diagnosis facility repair must derive the patient from the parent encounter');
must(diagnosisRepairBranch,/public\.current_user_facility_id\(\)/i,'authenticated diagnosis workflow may recover a missing parent facility from the active user facility');
must(diagnosisRepairBranch,/UPDATE public\.patients p SET facility_id=v_facility[\s\S]*FROM public\.encounters e[\s\S]*p\.id=e\.patient_id/i,'diagnosis facility recovery must update the patient through the parent encounter');
assert.doesNotMatch(diagnosisRepairBranch,/new\.patient_id/i,'diagnosis facility recovery must not read NEW.patient_id');
const reconciliationTriggerBranch = facility.match(/elsif tg_table_name='diagnoses' then([\s\S]*?)if v_facility is null then raise exception/i)?.[1] ?? '';
must(reconciliationTriggerBranch,/join public\.patients p on p\.id=e\.patient_id/i,'facility reconciliation trigger must derive diagnosis patient from the encounter');
assert.doesNotMatch(reconciliationTriggerBranch,/new\.patient_id/i,'facility reconciliation trigger must not read NEW.patient_id');
const diagnosisInventory = read('supabase/migrations/20260930015100_extend_facility_reconciliation_inventory.sql');
must(diagnosisInventory,/select 'diagnoses',d\.id,e\.patient_id[\s\S]{0,200}from public\.diagnoses d join public\.encounters e on e\.id=d\.encounter_id/i,'facility inventory must derive diagnosis patient identity through encounters');
const finalDiagnosisInventory = read('supabase/migrations/20261024070000_reconcile_clinical_facility_unresolved_record_query.sql');
must(finalDiagnosisInventory,/select 'diagnoses',d\.id,e\.patient_id[\s\S]{0,200}from public\.diagnoses d join public\.encounters e on e\.id=d\.encounter_id/i,'final facility inventory must derive diagnosis patient identity through encounters');
const canteenDiagnosisContext = read('supabase/migrations/20260929152000_restrict_canteen_patient_context_fields.sql');
must(canteenDiagnosisContext,/FROM public\.diagnoses d\s+JOIN public\.encounters e ON e\.id=d\.encounter_id AND e\.patient_id=p\.id\s+WHERE e\.status NOT IN/i,'canteen patient context must join diagnoses to the matching patient encounter');
const canteenBaseContext = read('supabase/migrations/20260929150000_canteen_dietary_operational_workspace.sql');
must(canteenBaseContext,/FROM public\.diagnoses d\s+JOIN public\.encounters e ON e\.id=d\.encounter_id AND e\.patient_id=p\.id\s+WHERE e\.status NOT IN/i,'base canteen patient context must join diagnoses to the matching patient encounter');
const resultsTranche = read('supabase/migrations/20261001230000_clinical_results_production_tranche.sql');
must(resultsTranche,/CREATE OR REPLACE FUNCTION public\.sync_child_facility_from_parent\(\)[\s\S]*?ELSIF tg_table_name='diagnoses' THEN[\s\S]*?JOIN public\.patients p ON p\.id=e\.patient_id/i,'forward lineage repair must replace the deployed diagnosis trigger with encounter-derived facility attribution');
const diagnosisTrigger = resultsTranche.match(/CREATE OR REPLACE FUNCTION public\.sync_child_facility_from_parent\(\)([\s\S]*?)\$function\$/i)?.[0] ?? '';
const diagnosisTriggerBranch = diagnosisTrigger.match(/ELSIF tg_table_name='diagnoses' THEN([\s\S]*?)END IF;/i)?.[1] ?? '';
assert.doesNotMatch(diagnosisTriggerBranch,/new\.patient_id/i,'diagnosis facility trigger must not read NEW.patient_id');
must(resultsTranche,/FROM public\.diagnoses d\s+JOIN public\.encounters diagnosis_encounter ON diagnosis_encounter\.id=d\.encounter_id[\s\S]*?diagnosis_encounter\.patient_id=io\.patient_id/i,'imaging results must match diagnoses through encounter patient lineage');
must(resultsTranche,/FROM public\.diagnoses d\s+JOIN public\.encounters diagnosis_encounter ON diagnosis_encounter\.id=d\.encounter_id[\s\S]*?diagnosis_encounter\.patient_id=o\.patient_id/i,'lab results must match diagnoses through encounter patient lineage');
for (const path of [
  'supabase/migrations/20261005190000_portal_clinical_continuity_and_clerking_referrals.sql',
  'supabase/migrations/20261006090000_patient_clinical_snapshot_facility_boundary.sql'
]) {
  const snapshot = read(path);
  must(snapshot,/FROM public\.diagnoses d\s+JOIN public\.encounters e ON e\.id=d\.encounter_id\s+WHERE e\.patient_id=_patient_id/i,'patient diagnosis snapshot must derive patient scope through encounters: '+path);
}
const patientHubSnapshot = read('supabase/migrations/20261007145000_reconcile_patient_hub_system_superuser_access.sql');
must(patientHubSnapshot,/FROM public\.diagnoses d JOIN public\.encounters e ON e\.id=d\.encounter_id WHERE e\.patient_id=_patient_id/i,'patient hub diagnosis history must be scoped through the encounter');
const labPanels = read('supabase/migrations/20261013180000_laboratory_test_panels.sql');
must(labPanels,/FROM public\.diagnoses d JOIN public\.encounters diagnosis_encounter ON diagnosis_encounter\.id=d\.encounter_id AND diagnosis_encounter\.patient_id=o\.patient_id/i,'laboratory panels must use encounter patient lineage for diagnoses');
// Preserve canonical facility payment-routing settings when upgrading legacy rows.
const ophthalmologyRoleMigration = read('supabase/migrations/20260912253900_add_ophthalmologist_app_role.sql');
must(ophthalmologyRoleMigration,/ALTER TYPE public\.app_role ADD VALUE IF NOT EXISTS 'ophthalmologist'/i,'ophthalmologist enum value must be committed before the ophthalmology workflow references it');
must(ophthalmologyRoleMigration,/ALTER TYPE public\.app_role ADD VALUE IF NOT EXISTS 'radiologist'/i,'radiologist enum value must be committed before outside-lab security policies reference it');
assert.ok(files.indexOf('20260912253900_add_ophthalmologist_app_role.sql') < files.indexOf('20260913008000_outside_lab_storage_security.sql'),'radiologist role enum migration must precede outside-lab security migration');
const itAdminRoleMigration = read('supabase/migrations/20260917149900_add_it_admin_app_role_prerequisite.sql');
must(itAdminRoleMigration,/ALTER TYPE public\.app_role ADD VALUE IF NOT EXISTS 'it_admin'/i,'IT administrator enum value must be committed before referral workflow functions reference it');
assert.ok(files.indexOf('20260917149900_add_it_admin_app_role_prerequisite.sql') < files.indexOf('20260917150000_clinical_admission_referral_document_lifecycle.sql'),'IT administrator enum prerequisite must precede clinical admission/referral lifecycle migration');
const permissionCatalog = read('supabase/migrations/20260918114000_database_permission_catalog.sql');
must(permissionCatalog,/is_active BOOLEAN NOT NULL DEFAULT TRUE/i,'permission catalog must default new permissions to active');
const functionalDomainPermissions = read('supabase/migrations/20260918133000_functional_domain_permissions.sql');
must(functionalDomainPermissions,/INSERT INTO public\.permissions\(permission_key, description\)[\s\S]*?ON CONFLICT\(permission_key\) DO UPDATE SET description=EXCLUDED\.description, is_active=TRUE/i,'functional-domain permission seed must rely on the catalog active default and reactivate existing keys');
assert.doesNotMatch(functionalDomainPermissions,/INSERT INTO public\.permissions\(permission_key, description, is_active\)/i,'functional-domain permission seed must not declare an is_active target without a corresponding value');
const serviceOrderWorkflow = read('supabase/migrations/20260918161000_reconcile_service_order_client_workflow.sql');
must(serviceOrderWorkflow,/DROP POLICY IF EXISTS "service_orders_staff_read" ON public\.service_orders;[\s\S]*?CREATE POLICY "service_orders_staff_read" ON public\.service_orders/i,'service-order client workflow must drop the policy created by the earlier HIMS workflow migration before recreating it');
const globalAuditTriggerRepair = read('supabase/migrations/20260917153900_harden_global_hims_audit_trigger_row_shape.sql');
must(globalAuditTriggerRepair,/CREATE OR REPLACE FUNCTION public\.audit_global_hims_change\(\)[\s\S]*?to_jsonb\(NEW\)->>'risk_level'/i,'shared HIMS audit trigger must read table-specific optional fields through JSON row projection');
assert.doesNotMatch(globalAuditTriggerRepair,/NEW\.risk_level/i,'generic audit trigger must not bind maternity-only columns to unrelated row types');
assert.ok(files.indexOf('20260917153900_harden_global_hims_audit_trigger_row_shape.sql') < files.indexOf('20260917154000_default_streamlined_clinical_routing.sql'),'generic audit trigger row-shape repair must precede facility-configuration updates');


assert.ok(files.indexOf('20260912253900_add_ophthalmologist_app_role.sql') < files.indexOf('20260912254000_ophthalmology_workflow.sql'),'ophthalmologist role enum migration must precede the ophthalmology workflow migration');
const reportsRecovery = read('supabase/migrations/20260914010028_reports_center_production_reconciliation.sql');
must(reportsRecovery,/DROP FUNCTION IF EXISTS public\.recover_stale_report_run\(UUID,INTEGER\)/i,'Reports Center reconciliation must explicitly drop the earlier BOOLEAN RPC before changing its return type');
must(reportsRecovery,/CREATE OR REPLACE FUNCTION public\.recover_stale_report_run\([\s\S]*?RETURNS public\.report_generation_runs/i,'Reports Center recovery RPC must preserve the production report_generation_runs return contract');
must(reportsRecovery,/REVOKE ALL ON FUNCTION public\.recover_stale_report_run\(UUID,INTEGER\) FROM PUBLIC, anon/i,'Reports Center recovery RPC must revoke PUBLIC and anon execution after recreation');
must(reportsRecovery,/GRANT EXECUTE ON FUNCTION public\.recover_stale_report_run\(UUID,INTEGER\) TO authenticated/i,'Reports Center recovery RPC must grant execution to authenticated users after recreation');
const pharmacyInventoryCompatibility = read('supabase/migrations/20260914140500_pharmacy_inventory_active_compatibility.sql');
must(pharmacyInventoryCompatibility,/ALTER TABLE public\.pharmacy_inventory\s+ADD COLUMN IF NOT EXISTS active BOOLEAN NOT NULL DEFAULT TRUE/i,'pharmacy inventory active compatibility column must be added before pharmacy lifecycle RPCs reference it');
assert.ok(files.indexOf('20260914140500_pharmacy_inventory_active_compatibility.sql') < files.indexOf('20260914141000_pharmacy_lifecycle_server_authority.sql'),'pharmacy inventory active compatibility migration must precede pharmacy lifecycle RPCs');
const workflowCompletion = read('supabase/migrations/20260912162001_hims_workflow_completion.sql');
must(workflowCompletion,/WHEN payment_routing_mode IN \('pay_before_every_step',\s*'streamlined'\)\s+THEN payment_routing_mode/i,'facility settings migration must preserve existing canonical payment-routing values');
must(workflowCompletion,/WHEN COALESCE\(to_jsonb\(facility_settings\)->>'routing_mode',''\) = 'pay_before_each_step'[\s\S]*?THEN 'pay_before_every_step'/i,'facility settings migration must translate the recognized legacy payment-routing value');
// Catch malformed single-dollar function openers and terminators before clean replay.
assert.ok(!all.includes('END;\n$;') && !all.includes('END;\r\n$;'),'migration chain must not contain a single-dollar PL/pgSQL function terminator');
// Do not reject tagged dollar-quote terminators such as $function$; the exact bare $; check above catches the malformed form.
const malformedOpeners = migrations.filter(({source}) => /\bAS\s+\$(?=\s|$)/.test(source)).map(({name}) => name);
assert.deepEqual(malformedOpeners, [], 'migration chain must not use single-dollar function openers: ' + malformedOpeners.join(', '));
const labRpcPrivileges = read('supabase/migrations/20261103092000_reassert_laboratory_read_rpc_privileges.sql');
must(labRpcPrivileges,/REVOKE ALL ON FUNCTION public\.get_laboratory_test_groups\(boolean\) FROM PUBLIC, anon/i,'laboratory test-group RPC must not be executable by anon or PUBLIC');
must(labRpcPrivileges,/GRANT EXECUTE ON FUNCTION public\.get_laboratory_test_groups\(boolean\) TO authenticated/i,'laboratory test-group RPC must remain available to authenticated users');
must(labRpcPrivileges,/REVOKE ALL ON FUNCTION public\.get_lab_result_attachments\(uuid\[\]\) FROM PUBLIC, anon/i,'laboratory attachment metadata RPC must not be executable by anon or PUBLIC');
must(labRpcPrivileges,/GRANT EXECUTE ON FUNCTION public\.get_lab_result_attachments\(uuid\[\]\) TO authenticated/i,'laboratory attachment metadata RPC must remain available to authenticated users');
const emergencyAcuityCompatibility = read('supabase/migrations/20261021100000_reconcile_emergency_case_acuity.sql');
must(emergencyAcuityCompatibility,/ADD COLUMN IF NOT EXISTS acuity TEXT NOT NULL DEFAULT 'urgent'/i,'emergency acuity compatibility must restore the legacy column before dependent indexes');
must(emergencyAcuityCompatibility,/ADD CONSTRAINT emergency_cases_acuity_check[\s\S]*?CHECK \(acuity IN \('resuscitation','emergency','urgent','less_urgent','non_urgent'\)\)/i,'emergency acuity compatibility must enforce the canonical acuity values');
const diagnosisImportSchema = read('supabase/migrations/20260916000000_restore_diagnosis_import_schema.sql');
for (const table of ['diagnosis_standards','stg_diagnoses','diagnosis_standard_mappings','diagnosis_import_batches','diagnosis_import_rows','facility_diagnosis_standards']) must(diagnosisImportSchema,new RegExp('CREATE TABLE IF NOT EXISTS public\\.'+table+'\\b','i'),'diagnosis import schema must restore '+table+' before the foreign-key index migration');
assert.ok(files.indexOf('20260916000000_restore_diagnosis_import_schema.sql') < files.indexOf('20260916103212_add_missing_foreign_key_indexes.sql'),'diagnosis import schema restoration must precede its foreign-key index migration');
must(diagnosisImportSchema,/ALTER TABLE public\.diagnosis_import_batches ENABLE ROW LEVEL SECURITY/i,'diagnosis import batches must retain row-level security');
must(diagnosisImportSchema,/CREATE POLICY facility_diagnosis_standards_authenticated_read[\s\S]*?USING \(is_active = true\)/i,'facility diagnosis standard mapping must remain authenticated-read-only and active-only');
must(diagnosisImportSchema,/diagnosis_import_batches_admin_insert[\s\S]*?public\.has_role\(auth\.uid\(\),'admin'::public\.app_role\)/i,'diagnosis import batch writes must be administrator-only using a helper available before the index migration');
must(diagnosisImportSchema,/diagnosis_import_rows_admin_update[\s\S]*?public\.has_role\(auth\.uid\(\),'admin'::public\.app_role\)/i,'diagnosis import row updates must be administrator-only using a helper available before the index migration');
const workflow = read('.github/workflows/migration-contract.yml');
must(workflow,/supabase db reset/i,'CI must replay migrations on a clean database');
must(workflow,/migration_contract\.sql/i,'CI must run live database migration contract');
must(workflow,/legacy schema compatibility contract/i,'CI must validate partial legacy-schema compatibility');
console.log('[migration-contract] schema, index, RPC return/security, attachment lineage and legacy-reconciliation checks passed; inspected '+files.length+' migrations and '+checked+' SECURITY DEFINER definitions.');
