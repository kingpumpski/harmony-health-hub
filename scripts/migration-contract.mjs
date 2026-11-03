import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
const root = process.cwd();
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
assert.doesNotMatch(reportSeedFoundation,/GET DIAGNOSTICS|RETURN v_count/i,'VOID report seeding must not retain the obsolete row-count return contract');
const reportSeedMigration = read('supabase/migrations/20260920211000_privileged_admin_resource_scope_hardening.sql');
must(reportSeedMigration,/CREATE OR REPLACE FUNCTION public\.seed_facility_reports\(_facility_id uuid\)\s+RETURNS void\b/i,'facility report seeding must preserve its established VOID RPC return type');
const reportSeedTypeTransition = read('supabase/migrations/20260914010028_reports_center_production_reconciliation.sql');
must(reportSeedTypeTransition,/DROP FUNCTION IF EXISTS public\.seed_facility_reports\(UUID\);[\s\S]*?CREATE OR REPLACE FUNCTION public\.seed_facility_reports\(_facility_id uuid\)\s+RETURNS void\b/i,'facility report seed return-type transition must explicitly drop and recreate the earlier INTEGER signature');
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
  [/facility_id IS NULL[\s\S]*?RAISE EXCEPTION/i,'legacy attachment facility scope must fail closed when missing rather than being guessed'],
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
const patientHubEntrypoints = read("supabase/migrations/20260923130000_patient_hub_entrypoint_context_hardening.sql");
must(patientHubEntrypoints,/GRANT EXECUTE ON FUNCTION public\.record_patient_vitals\(UUID,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC\) TO authenticated/i,"patient vitals grant must match the nine-argument RPC signature");
const facility = read('supabase/migrations/20260930014000_clinical_facility_reconciliation_control_plane.sql');
const labResultBranch = facility.match(/elsif _entity_type='lab_results' then([\s\S]*?)elsif _entity_type='imaging_orders' then/i)?.[1] ?? '';
assert.ok(labResultBranch, 'clinical facility reconciliation must retain a lab_results branch');
assert.doesNotMatch(labResultBranch, /\br\.patient_id\b/i, 'lab_results reconciliation must not read patient_id from lab_results');
must(labResultBranch,/left join public\.lab_orders lo on lo\.id=r\.lab_order_id/i,'lab_results reconciliation must join the parent lab order');
must(labResultBranch,/\blo\.patient_id\b/i,'lab_results reconciliation must derive patient lineage through the parent lab order');
must(labResultBranch,/lr\.patient_id IS NOT NULL AND lr\.patient_id IS DISTINCT FROM lo\.patient_id/i,'lab_results reconciliation must fail closed when legacy patient_id conflicts with the parent order');
// Diagnosis patient identity is canonicalized through encounters; the legacy nullable diagnoses.patient_id field is not authoritative and is absent from the clean-install schema.
const diagnosisFacilityBranch = facility.match(/elsif _entity_type='diagnoses' then([\\s\\S]*?)else raise exception 'Unsupported clinical entity type'/i)?.[1] ?? '';
must(diagnosisFacilityBranch,/join public\\.encounters e on e\\.id=d\\.encounter_id/i,'facility reconciliation must resolve diagnosis patient identity through its encounter');
must(diagnosisFacilityBranch,/coalesce\\(e\\.facility_id,p\\.facility_id\\)/i,'diagnosis facility reconciliation must fall back through the encounter patient');
assert.doesNotMatch(diagnosisFacilityBranch,/\\bd\\.patient_id\\b/i,'diagnosis reconciliation must not depend on the nullable legacy patient_id column');
const diagnosisInventory = read('supabase/migrations/20260930015100_extend_facility_reconciliation_inventory.sql');
must(diagnosisInventory,/select 'diagnoses',d\\.id,e\\.patient_id[\\s\\S]{0,200}from public\\.diagnoses d join public\\.encounters e on e\\.id=d\\.encounter_id/i,'facility inventory must derive diagnosis patient identity through encounters');
const canteenDiagnosisContext = read('supabase/migrations/20260929152000_restrict_canteen_patient_context_fields.sql');
must(canteenDiagnosisContext,/FROM public\\.diagnoses d\\s+JOIN public\\.encounters e ON e\\.id=d\\.encounter_id AND e\\.patient_id=p\\.id\\s+WHERE e\\.status NOT IN/i,'canteen patient context must join diagnoses to the matching patient encounter');
const resultsTranche = read('supabase/migrations/20261001230000_clinical_results_production_tranche.sql');
must(resultsTranche,/CREATE OR REPLACE FUNCTION public\\.sync_child_facility_from_parent\\(\\)[\\s\\S]*?ELSIF tg_table_name='diagnoses' THEN[\\s\\S]*?JOIN public\\.patients p ON p\\.id=e\\.patient_id/i,'forward lineage repair must replace the deployed diagnosis trigger with encounter-derived facility attribution');
const diagnosisTrigger = resultsTranche.match(/CREATE OR REPLACE FUNCTION public\\.sync_child_facility_from_parent\\(\\)([\\s\\S]*?)\\$function\\$/i)?.[0] ?? '';
const diagnosisTriggerBranch = diagnosisTrigger.match(/ELSIF tg_table_name='diagnoses' THEN([\\s\\S]*?)END IF;/i)?.[1] ?? '';
assert.doesNotMatch(diagnosisTriggerBranch,/new\\.patient_id/i,'diagnosis facility trigger must not read NEW.patient_id');
must(resultsTranche,/FROM public\\.diagnoses d\\s+JOIN public\\.encounters diagnosis_encounter ON diagnosis_encounter\\.id=d\\.encounter_id[\\s\\S]*?diagnosis_encounter\\.patient_id=io\\.patient_id/i,'imaging results must match diagnoses through encounter patient lineage');
must(resultsTranche,/FROM public\\.diagnoses d\\s+JOIN public\\.encounters diagnosis_encounter ON diagnosis_encounter\\.id=d\\.encounter_id[\\s\\S]*?diagnosis_encounter\\.patient_id=o\\.patient_id/i,'lab results must match diagnoses through encounter patient lineage');
const patientHubSnapshot = read('supabase/migrations/20261007145000_reconcile_patient_hub_system_superuser_access.sql');
must(patientHubSnapshot,/FROM public\\.diagnoses d JOIN public\\.encounters e ON e\\.id=d\\.encounter_id WHERE e\\.patient_id=_patient_id/i,'patient hub diagnosis history must be scoped through the encounter');
const labPanels = read('supabase/migrations/20261013180000_laboratory_test_panels.sql');
must(labPanels,/FROM public\\.diagnoses d JOIN public\\.encounters diagnosis_encounter ON diagnosis_encounter\\.id=d\\.encounter_id AND diagnosis_encounter\\.patient_id=o\\.patient_id/i,'laboratory panels must use encounter patient lineage for diagnoses');
// Preserve canonical facility payment-routing settings when upgrading legacy rows.
const workflowCompletion = read('supabase/migrations/20260912162001_hims_workflow_completion.sql');
must(workflowCompletion,/WHEN payment_routing_mode IN \\('pay_before_every_step',\\s*'streamlined'\\)\\s+THEN payment_routing_mode/i,'facility settings migration must preserve existing canonical payment-routing values');
must(workflowCompletion,/WHEN COALESCE\\(to_jsonb\\(facility_settings\\)->>'routing_mode',''\\) = 'pay_before_each_step'[\\s\\S]*?THEN 'pay_before_every_step'/i,'facility settings migration must translate the recognized legacy payment-routing value');
// Catch malformed single-dollar function openers and terminators before clean replay.
assert.ok(!all.includes('END;\n$;') && !all.includes('END;\r\n$;'),'migration chain must not contain a single-dollar PL/pgSQL function terminator');
// Do not reject tagged dollar-quote terminators such as $function$; the exact bare $; check above catches the malformed form.
const malformedOpeners = migrations.filter(({source}) => /\bAS\s+\$(?=\s|$)/.test(source)).map(({name}) => name);
assert.deepEqual(malformedOpeners, [], 'migration chain must not use single-dollar function openers: ' + malformedOpeners.join(', '));
const workflow = read('.github/workflows/migration-contract.yml');
must(workflow,/supabase db reset/i,'CI must replay migrations on a clean database');
must(workflow,/migration_contract\.sql/i,'CI must run live database migration contract');
must(workflow,/legacy schema compatibility contract/i,'CI must validate partial legacy-schema compatibility');
console.log('[migration-contract] schema, index, RPC return/security, attachment lineage and legacy-reconciliation checks passed; inspected '+files.length+' migrations and '+checked+' SECURITY DEFINER definitions.');
