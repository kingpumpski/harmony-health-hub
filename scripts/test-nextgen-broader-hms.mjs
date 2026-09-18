import fs from 'node:fs';
import path from 'node:path';

const root=process.cwd();
const read=(p)=>fs.readFileSync(path.join(root,p),'utf8');
const assert=(ok,msg)=>{if(!ok) throw new Error(msg)};

const registry=JSON.parse(read('platform/reference/module-registry.json'));
assert(registry.schemaVersion==='1.0.0','module registry schema must remain verifier-compatible');
for(const id of ['physiotherapy','dietary-restaurant','teaching-research','asset-biomedical','procurement','data-import','report-centre','user-role-management']) assert(registry.modules.some(m=>m.id===id),`missing broader module: ${id}`);

const manifest=read('src/lib/nextGenModuleManifest.ts');
for(const id of ['physiotherapy','dietary-restaurant','teaching-research','asset-biomedical','procurement','data-import','report-centre','user-role-management']) assert(manifest.includes(`id: '${id}'`),`missing broader module contract: ${id}`);

const migration=read('supabase/migrations/20260918170000_broader_hms_enterprise_foundation.sql');
const importWorkflow=read('supabase/migrations/20260918180000_hms_import_governed_lifecycle.sql');
const importTemplate=read('supabase/migrations/20260918190000_hms_import_patient_template.sql');
const importUi=read('src/pages/admin/DataImport.tsx');
for (const token of ['create_hms_import_batch','validate_hms_import_batch','approve_hms_import_batch','commit_hms_import_batch','rollback_hms_import_batch']) assert(importWorkflow.includes(token),`missing governed import workflow: ${token}`);
assert(importWorkflow.includes('Only approved batches may be committed') && importWorkflow.includes('Atomic'), 'import approval/atomic boundary missing');
assert(importTemplate.includes('TMPL-PAT-PATIENT-v1'), 'patient import template missing');
assert(importUi.includes("create_hms_import_batch") && importUi.includes("commit_hms_import_batch"), 'Data Import UI is not using governed import workflow');
assert(!importUi.includes("supabase.from('patients').insert"), 'Data Import UI must not write directly to patients');
for(const token of [
 'hms_facility_modules','set_hms_facility_module','hms_role_catalog','hms_role_module_permissions',
 'hms_import_templates','hms_import_template_versions','hms_import_batches','hms_import_staging','hms_import_quarantine','hms_import_audit',
 'hms_report_templates','hms_report_runs','hms_report_submissions','hms_procurement_suppliers','hms_purchase_orders',
 'hms_biomedical_assets','hms_biomedical_maintenance','hms_physio_assessments','hms_physio_sessions',
 'hms_teaching_research_projects','hms_teaching_research_dataset_requests','audit_clinical_record_change'
]) assert(migration.includes(token),`broader HMS foundation missing: ${token}`);

const docs=read('docs/next-gen-hims/23-MASTER-SPECIFICATION-RECONCILIATION.md');
assert(docs.includes('single canonical HMS/HIMS') && docs.includes('No new module may introduce a second'), 'canonical consolidation rule missing');

console.log(`Broader HMS contract passed: ${registry.modules.length} registry modules; import, Report Centre, enterprise roles, facility gates, procurement, biomedical, physiotherapy, dietary and teaching/research boundaries present.`);
