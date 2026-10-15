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
must(all,/CREATE OR REPLACE FUNCTION public\\.get_laboratory_test_groups\\([^)]*\\)[\\s\\S]*?RETURNS\\s+jsonb[\\s\\S]*?SECURITY DEFINER[\\s\\S]*?SET search_path\\s*=/i,'panel RPC must pin search_path and return jsonb');
must(all,/CREATE OR REPLACE FUNCTION public\\.get_lab_result_attachments\\([^)]*\\)[\\s\\S]*?RETURNS\\s+jsonb[\\s\\S]*?SECURITY DEFINER[\\s\\S]*?SET search_path\\s*=/i,'attachment RPC must pin search_path and return jsonb');
const attachment = read('supabase/migrations/20261014120000_harden_lab_result_attachment_read_rpc.sql');
for (const [r,m] of [
  [/a\.facility_id = v_facility/,'attachment read must be facility-scoped'],
  [/JOIN public\.patients p[\s\S]*?p\.facility_id = lo\.facility_id/,'attachment read must verify patient/order facility lineage'],
  [/lr\.lab_order_id = lo\.id[\s\S]*?lr\.patient_id = lo\.patient_id[\s\S]*?lr\.facility_id = lo\.facility_id/,'attachment read must verify result/order/patient/facility lineage'],
  [/so\.related_entity_id = coalesce\(lo\.parent_order_id, lo\.id\)[\s\S]*?so\.status IN \('released', 'in_progress', 'completed'\)/,'attachment read must require parent-aware billing release'],
  [/REVOKE ALL ON FUNCTION public\.get_lab_result_attachments\(uuid\[\]\) FROM PUBLIC, anon/i,'attachment RPC must revoke PUBLIC and anon'],
  [/GRANT EXECUTE ON FUNCTION public\.get_lab_result_attachments\(uuid\[\]\) TO authenticated/i,'attachment RPC must grant only authenticated execution'],
]) must(attachment,r,m);
const fn = /CREATE(?: OR REPLACE)? FUNCTION public\.[\s\S]*?\bSECURITY DEFINER\b[\s\S]*?(?=CREATE(?: OR REPLACE)? FUNCTION public\.|$)/gi;
let checked=0;
for (const {name,source} of migrations) for (const match of source.matchAll(fn)) {
  must(match[0],/SET\\s+search_path\\s*=/i,name+': SECURITY DEFINER function must pin search_path');
  assert.doesNotMatch(match[0],/SET\s+search_path\s*=\s*['"]?public\b/i,name+': public cannot be trusted in search_path');
  checked++;
}
const legacy = read('supabase/migrations/20261015060000_reconcile_missing_laboratory_objects.sql');
for (const [r,m] of [
  [/CREATE TABLE IF NOT EXISTS public\.lab_test_groups/i,'legacy repair must tolerate existing panel table'],
  [/CREATE TABLE IF NOT EXISTS public\.lab_test_group_items/i,'legacy repair must tolerate existing membership table'],
  [/ADD COLUMN IF NOT EXISTS group_id/i,'legacy repair must tolerate existing lab_orders.group_id'],
  [/ADD COLUMN IF NOT EXISTS parent_order_id/i,'legacy repair must tolerate existing lab_orders.parent_order_id'],
  [/CREATE TABLE IF NOT EXISTS public\.lab_result_attachments/i,'legacy repair must tolerate existing attachment table'],
  [/CREATE OR REPLACE FUNCTION public\.get_lab_result_attachments\(_lab_order_ids uuid\[\]\)/i,'legacy repair must restore canonical attachment RPC'],
]) must(legacy,r,m);
const workflow = read('.github/workflows/migration-contract.yml');
must(workflow,/supabase db reset/i,'CI must replay migrations on a clean database');
must(workflow,/migration_contract\.sql/i,'CI must run live database migration contract');
must(workflow,/legacy schema compatibility contract/i,'CI must validate partial legacy-schema compatibility');
console.log('[migration-contract] schema, index, RPC return/security, attachment lineage and legacy-reconciliation checks passed; inspected '+files.length+' migrations and '+checked+' SECURITY DEFINER definitions.');
