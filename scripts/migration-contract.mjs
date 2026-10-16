import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
const root = process.cwd();
const dir = path.join(root, 'supabase', 'migrations');
const files = fs.readdirSync(dir).filter((n) => /^\d{14}_.+\.sql$/.test(n)).sort();
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
const attachment = read('supabase/migrations/20261014120000_harden_lab_result_attachment_read_rpc.sql');
for (const [r,m] of [
  [/a\.facility_id = v_facility/,'attachment read must be facility-scoped'],
  [/JOIN public\.patients p[\s\S]*?p\.facility_id = lo\.facility_id/,'attachment read must verify patient/order facility lineage'],
  [/lr\.lab_order_id = lo\.id[\s\S]*?lr\.patient_id = lo\.patient_id[\s\S]*?lr\.facility_id = lo\.facility_id/,'attachment read must verify result/order/patient/facility lineage'],
  [/so\.related_entity_id = coalesce\(lo\.parent_order_id, lo\.id\)[\s\S]*?so\.status IN \('released', 'in_progress', 'completed'\)/,'attachment read must require parent-aware billing release'],
  [/REVOKE ALL ON FUNCTION public\.get_lab_result_attachments\(uuid\[\]\) FROM PUBLIC, anon/i,'attachment RPC must revoke PUBLIC and anon'],
  [/GRANT EXECUTE ON FUNCTION public\.get_lab_result_attachments\(uuid\[\]\) TO authenticated/i,'attachment RPC must grant only authenticated execution'],
]) must(attachment,r,m);
const fn = /CREATE(?: OR REPLACE)? FUNCTION public\.([a-zA-Z0-9_]+)\s*\([\s\S]*?(?=CREATE(?: OR REPLACE)? FUNCTION public\.|$)/gi;
let checked=0;
for (const {name,source} of migrations) {
  // SQL comments may mention SECURITY DEFINER; they must not influence executable-code checks.
  const executableSource = source.replace(/--.*$/gm, '');
  for (const match of executableSource.matchAll(fn)) {
  // Inspect one function definition at a time; never let a later SECURITY DEFINER
  // declaration make an earlier trigger/helper look security-definer by accident.
  if (!/\bSECURITY DEFINER\b/i.test(match[0])) continue;
  must(match[0],/SET\s+search_path\s*(?:=|TO\s+)/i,name+': SECURITY DEFINER function must pin search_path');
  const functionName = match[1];
  const unsafePublicOnlyPath = /SET\s+search_path\s*(?:=|TO\s+)\s*['"]?public\b/i.test(match[0]);
  if (unsafePublicOnlyPath) {
    const later = migrations.filter(candidate => candidate.name > name).map(candidate => candidate.source).join('\n');
    const hardeningPath = "(?:pg_catalog\\s*,\\s*public|''|\"\")";
    const hardenedLater =
      new RegExp('ALTER\\s+FUNCTION\\s+public\\.' + functionName + '\\s*\\([^;]*?\\)\\s+SET\\s+search_path\\s*=\\s*' + hardeningPath, 'i').test(later)
      || new RegExp('CREATE(?: OR REPLACE)? FUNCTION\\s+public\\.' + functionName + '\\s*\\([^)]*\\)[\\s\\S]*?SECURITY DEFINER[\\s\\S]*?SET\\s+search_path\\s*=\\s*' + hardeningPath, 'i').test(later);
    assert.ok(hardenedLater, name+': unsafe SECURITY DEFINER search_path lacks later hardening: '+functionName);
  }
  checked++;
  }
}
const legacy = read('supabase/migrations/20261015060000_reconcile_missing_laboratory_objects.sql');
must(legacy, /CREATE INDEX IF NOT EXISTS idx_lab_result_attachments_uploaded_by\s+ON public\.lab_result_attachments\(uploaded_by\)/i, 'attachment uploader foreign key must have a covering index');
for (const [r,m] of [
  [/CREATE TABLE IF NOT EXISTS public\.lab_test_groups/i,'legacy repair must tolerate existing panel table'],
  [/CREATE TABLE IF NOT EXISTS public\.lab_test_group_items/i,'legacy repair must tolerate existing membership table'],
  [/ADD COLUMN IF NOT EXISTS group_id/i,'legacy repair must tolerate existing lab_orders.group_id'],
  [/ADD COLUMN IF NOT EXISTS parent_order_id/i,'legacy repair must tolerate existing lab_orders.parent_order_id'],
  [/CREATE TABLE IF NOT EXISTS public\.lab_result_attachments/i,'legacy repair must tolerate existing attachment table'],
  [/CREATE OR REPLACE FUNCTION public\.get_lab_result_attachments\(_lab_order_ids uuid\[\]\)/i,'legacy repair must restore canonical attachment RPC'],
]) must(legacy,r,m);
const patientContinuityHardening = read('supabase/migrations/20261016100000_reconcile_lab_parameter_order_and_harden_patient_continuity.sql');
const patientEntrypointMigration = read('supabase/migrations/20260923130000_patient_hub_entrypoint_context_hardening.sql');
must(patientEntrypointMigration, /GRANT EXECUTE ON FUNCTION public\.record_patient_vitals\(UUID,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC\) TO authenticated/i, 'vitals RPC grant must match its nine-argument signature');
for (const [pattern, label] of [
  [/ALTER FUNCTION public\.create_encounter_workflow\(uuid, text, text\)\s+SET search_path = ''/i, 'encounter entrypoint'],
  [/ALTER FUNCTION public\.record_patient_vitals\(uuid, numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric\)\s+SET search_path = ''/i, 'vitals entrypoint'],
  [/ALTER FUNCTION public\.create_patient_lab_order\(uuid, text, text\)\s+SET search_path = ''/i, 'lab-order entrypoint'],
  [/ALTER FUNCTION public\.create_patient_document\(uuid, text, text, text\)\s+SET search_path = ''/i, 'patient-document entrypoint'],
]) must(patientContinuityHardening, pattern, label + ' must be re-hardened after the public-only override');
const workflowReconciliation = read('supabase/migrations/20260912162001_hims_workflow_completion.sql');
must(workflowReconciliation, /ALTER TABLE public\.inpatient_reviews\s+ADD COLUMN IF NOT EXISTS seen_at TIMESTAMPTZ NOT NULL DEFAULT now\(\)/i, 'legacy inpatient reviews must receive seen_at before dependent indexes');
assert.ok(workflowReconciliation.indexOf('ADD COLUMN IF NOT EXISTS seen_at') < workflowReconciliation.indexOf('CREATE INDEX IF NOT EXISTS inpatient_reviews_admission_idx'), 'inpatient review timestamp must be reconciled before index creation');
must(workflowReconciliation, /ALTER TABLE public\.patient_audit\s+ADD COLUMN IF NOT EXISTS changed_at TIMESTAMPTZ NOT NULL DEFAULT now\(\)/i, 'legacy patient audit table must receive changed_at before its index');
assert.ok(workflowReconciliation.indexOf('ADD COLUMN IF NOT EXISTS changed_at') < workflowReconciliation.indexOf('CREATE INDEX IF NOT EXISTS patient_audit_patient_idx'), 'patient audit timestamp must be reconciled before index creation');
must(patientContinuityHardening, /ALTER FUNCTION public\.get_patient_hub_snapshot\(uuid\) SET search_path = ''/i, 'patient hub snapshot SECURITY DEFINER must be re-hardened');
must(patientContinuityHardening, /ALTER FUNCTION public\.get_laboratory_test_groups\(boolean\) SET search_path = ''/i, 'laboratory panel read RPC must be re-hardened');
must(patientContinuityHardening, /ALTER FUNCTION public\.get_lab_result_attachments\(uuid\[\]\) SET search_path = ''/i, 'laboratory attachment read RPC must be re-hardened');
must(patientContinuityHardening, /ALTER FUNCTION public\.ensure_updated_at\(\) SET search_path = ''/i, 'timestamp trigger helper must pin search_path');
must(patientContinuityHardening, /DROP INDEX IF EXISTS public\.lab_result_attachments_result_idx/i, 'duplicate legacy attachment result index must be removed');
for (const [r,m] of [
  [/ADD COLUMN IF NOT EXISTS sort_order INTEGER NOT NULL DEFAULT 0/i,'legacy lab parameter ordering column must be reconciled before its index'],
  [/ADD COLUMN IF NOT EXISTS fulfillment_status TEXT NOT NULL DEFAULT 'blocked'/i,'legacy service-order fulfillment state must be reconciled before indexing'],
  [/ADD COLUMN IF NOT EXISTS payment_status TEXT NOT NULL DEFAULT 'pending'/i,'legacy service-order payment state must be reconciled'],
  [/ADD COLUMN IF NOT EXISTS payment_routing_mode TEXT NOT NULL DEFAULT 'streamlined'/i,'legacy facility routing mode must be reconciled'],
]) must(workflowReconciliation,r,m);
assert.ok(
  workflowReconciliation.indexOf('ADD COLUMN IF NOT EXISTS fulfillment_status') < workflowReconciliation.indexOf('CREATE INDEX IF NOT EXISTS service_orders_queue_idx'),
  'legacy service-order columns must be reconciled before queue index creation',
);
const workflow = read('.github/workflows/migration-contract.yml');
must(workflow,/supabase db reset/i,'CI must replay migrations on a clean database');
must(workflow,/migration_contract\.sql/i,'CI must run live database migration contract');
must(workflow,/legacy schema compatibility contract/i,'CI must validate partial legacy-schema compatibility');
console.log('[migration-contract] schema, index, RPC return/security, attachment lineage and legacy-reconciliation checks passed; inspected '+files.length+' migrations and '+checked+' SECURITY DEFINER definitions.');
