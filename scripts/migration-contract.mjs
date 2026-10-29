import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
const root = process.cwd();
const dir = path.join(root, 'supabase', 'migrations');
const sqlFiles = fs.readdirSync(dir).filter((n) => n.endsWith('.sql')).sort();
for (const name of sqlFiles) assert.match(name, /^\d{14}_.+\.sql$/, `Invalid migration filename (expected <14-digit-version>_<name>.sql): ${name}`);
const files = sqlFiles;
const versions = new Map();
for (const name of files) {
  const version = name.slice(0, 14);
  const previous = versions.get(version);
  assert.equal(previous, undefined, `Duplicate Supabase migration version ${version}: ${previous ?? ''} and ${name}`);
  versions.set(version, name);
}
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
must(claimTransitionMigration,/CREATE OR REPLACE FUNCTION public\.transition_insurance_claim_canonical\([\s\S]*?\)\s*RETURNS\s+JSONB\b/i,'claim transition hardening must preserve the established JSONB RPC return type');
const reportSeedMigration = read('supabase/migrations/20260920211000_privileged_admin_resource_scope_hardening.sql');
must(reportSeedMigration,/CREATE OR REPLACE FUNCTION public\.seed_facility_reports\(_facility_id uuid\)\s+RETURNS integer\b/i,'facility report seeding must preserve its established INTEGER RPC return type');
must(reportSeedMigration,/GET DIAGNOSTICS v_count = ROW_COUNT;\s+RETURN v_count;/i,'facility report seeding must return the affected row count');
const legacy = read('supabase/migrations/20261015060000_reconcile_missing_laboratory_objects.sql');
for (const [r,m] of [
  [/CREATE TABLE IF NOT EXISTS public\.lab_test_groups/i,'legacy repair must tolerate existing panel table'],
  [/CREATE TABLE IF NOT EXISTS public\.lab_test_group_items/i,'legacy repair must tolerate existing membership table'],
  [/ADD COLUMN IF NOT EXISTS group_id/i,'legacy repair must tolerate existing lab_orders.group_id'],
  [/ADD COLUMN IF NOT EXISTS parent_order_id/i,'legacy repair must tolerate existing lab_orders.parent_order_id'],
  [/CREATE TABLE IF NOT EXISTS public\.lab_result_attachments/i,'legacy repair must tolerate existing attachment table'],
  [/ALTER TABLE public\.lab_result_attachments[\s\S]*?ADD COLUMN IF NOT EXISTS lab_order_id uuid/i,'legacy repair must reconcile missing attachment order linkage'],
  [/ALTER TABLE public\.lab_result_attachments[\s\S]*?ADD COLUMN IF NOT EXISTS lab_result_id uuid/i,'legacy repair must reconcile missing attachment result linkage'],
  [/ALTER TABLE public\.lab_result_attachments[\s\S]*?ADD COLUMN IF NOT EXISTS facility_id uuid/i,'legacy repair must reconcile missing attachment facility scope'],
  [/ALTER TABLE public\.lab_result_attachments[\s\S]*?ADD COLUMN IF NOT EXISTS storage_path text/i,'legacy repair must reconcile missing storage path metadata'],
  [/ALTER TABLE public\.lab_result_attachments[\s\S]*?ADD COLUMN IF NOT EXISTS file_size_bytes bigint/i,'legacy repair must reconcile missing attachment size metadata'],
  [/UPDATE public\.lab_result_attachments[\s\S]*?SET id = gen_random_uuid\(\)[\s\S]*?WHERE id IS NULL/i,'legacy attachment identifiers must be backfilled'],
  [/row_number\(\) OVER \(PARTITION BY id/i,'duplicate legacy attachment identifiers must be repaired before uniqueness enforcement'],
  [/CREATE UNIQUE INDEX IF NOT EXISTS lab_result_attachments_id_legacy_uidx/i,'legacy attachment identifiers must be unique after reconciliation'],
  [/UPDATE public\.lab_result_attachments AS attachment[\s\S]*?WHERE attachment\.facility_id IS NULL[\s\S]*?attachment\.lab_order_id = lo\.id/i,'legacy facility scope may only be backfilled from an explicit order link'],
  [/CREATE UNIQUE INDEX IF NOT EXISTS lab_result_attachments_storage_path_legacy_uidx/i,'legacy storage paths must be unique when existing data allows it'],
  [/file_size_bytes BETWEEN 1 AND 15728640/i,'attachment metadata writes must validate file size'],
  [/duplicate\.storage_path = a\.storage_path[\s\S]*?duplicate\.id <> a\.id/i,'ambiguous legacy storage paths must fail closed'],
  [/CREATE OR REPLACE FUNCTION public\.get_lab_result_attachments\(_lab_order_ids uuid\[\]\)/i,'legacy repair must restore canonical attachment RPC'],
  [/CREATE UNIQUE INDEX IF NOT EXISTS lab_result_attachments_storage_path_legacy_uidx/i,'effective attachment RPC migration must conditionally enforce unique storage paths'],
  [/AND a\.storage_path IS NOT NULL[\s\S]*?AND NOT EXISTS \(\s*SELECT 1[\s\S]*?duplicate\.storage_path = a\.storage_path/i,'effective attachment RPC must fail closed for incomplete and duplicate paths'],
]) must(legacy,r,m);
// Guard partial legacy schemas: missing audit tables are valid, and canonical
// tariff aliases must satisfy installations where service_tariffs.category is NOT NULL.
const patientAuditRetention = read('supabase/migrations/20260912002000_phase5_patient_audit_retention.sql');
must(patientAuditRetention,/IF to_regclass\('public\.patient_audit_log'\) IS NOT NULL THEN/i,'patient audit retention must guard absent legacy patient_audit_log tables');
must(patientAuditRetention,/ELSIF to_regclass\('public\.patient_audit'\) IS NOT NULL THEN/i,'patient audit retention must support the canonical patient_audit table');
const canonicalTariffs = read('supabase/migrations/20260919055127_reconcile_remaining_canonical_service_tariff_codes.sql');
must(canonicalTariffs,/INSERT INTO public\.service_tariffs\s*\(\s*service_code,\s*service_name,\s*category,\s*department,\s*unit,\s*amount,\s*active,\s*currency,\s*metadata\s*\)/i,'canonical tariff aliases must explicitly populate required category');
must(canonicalTariffs,/category\s*=\s*EXCLUDED\.category/i,'canonical tariff upserts must reconcile category on existing aliases');
const facility = read('supabase/migrations/20260930014000_clinical_facility_reconciliation_control_plane.sql');
const labResultBranch = facility.match(/elsif _entity_type='lab_results' then([\s\S]*?)elsif _entity_type='imaging_orders' then/i)?.[1] ?? '';
assert.ok(labResultBranch, 'clinical facility reconciliation must retain a lab_results branch');
assert.doesNotMatch(labResultBranch, /\br\.patient_id\b/i, 'lab_results reconciliation must not read patient_id from lab_results');
must(labResultBranch,/left join public\.lab_orders lo on lo\.id=r\.lab_order_id/i,'lab_results reconciliation must join the parent lab order');
must(labResultBranch,/\blo\.patient_id\b/i,'lab_results reconciliation must derive patient lineage through the parent lab order');
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
