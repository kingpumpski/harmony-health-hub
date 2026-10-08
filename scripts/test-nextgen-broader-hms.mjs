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

const serviceExpansion=read('supabase/migrations/20261008130000_hms_service_availability_and_enterprise_modules.sql');
const portalRuntime=read('supabase/migrations/20261006095000_patient_portal_self_service_runtime_reconciliation.sql');
const portal=read('supabase/migrations/20261008140000_reconcile_patient_portal_and_telemedicine.sql');
const enterprise=read('supabase/migrations/20261008150000_enterprise_workflow_completion.sql');
const telemedicine=read('supabase/migrations/20261008151000_harden_telemedicine_clinician_availability.sql');
const facilityScope=read('supabase/migrations/20261008152000_harden_facility_module_configuration_scope.sql');
const enterpriseUi=read('src/pages/EnterpriseModuleWorkspace.tsx');
const appointmentsUi=read('src/pages/Appointments.tsx');
const mealsUi=read('src/pages/CanteenMeals.tsx');
const app=read('src/App.tsx');
for(const id of ['hr-payroll','icu-critical-care','mental-health','social-work','quality-compliance','infection-control','mortuary','ambulance','research-portal','external-audit','genomics']) assert(registry.modules.some(m=>m.id===id),`missing enterprise expansion module: ${id}`);
for(const id of ['hr-payroll','icu-critical-care','mental-health','social-work','quality-compliance','infection-control','mortuary','ambulance','research-portal','external-audit','genomics']) assert(manifest.includes(`id: '${id}'`),`missing enterprise expansion contract: ${id}`);
for(const token of ['service_available','readiness_status','set_hms_facility_module_service','hms_user_role_assignments','hms_hr_employees','hms_payroll_periods','hms_icu_stays','hms_mental_health_assessments','hms_social_work_cases','hms_quality_incidents','hms_ipc_events','hms_mortuary_cases','hms_ambulance_trips','hms_research_projects','hms_audit_engagements','hms_genomics_orders']) assert(serviceExpansion.includes(token),`service/enterprise boundary missing: ${token}`);
for(const token of ['get_patient_portal_video_sessions','get_patient_telemedicine_clinicians','create_patient_appointment','get_patient_portal_meal_menus','get_patient_outside_lab_documents']) assert(portalRuntime.includes(token),`patient portal runtime boundary missing: ${token}`);
for(const token of ['get_patient_portal_identity','get_patient_appointments','get_patient_invoice_summary','request_patient_telemedicine_session','patient own appointments select']) assert(portal.includes(token),`patient portal boundary missing: ${token}`);
for(const token of ['create_patient_appointment','Request Appointment']) assert(appointmentsUi.includes(token),`patient appointment self-service UI missing: ${token}`);
assert(mealsUi.includes('get_patient_portal_meal_menus') && mealsUi.includes("user?.role === 'patient'"), 'patient meal menu must be server-gated and role-separated');
for(const token of ['hms_user_can','hms_assert_enterprise_access','set_hms_specialist_role','get_hms_my_specialist_roles','hms_get_enterprise_workspace','hms_create_enterprise_record']) assert(enterprise.includes(token),`enterprise workflow boundary missing: ${token}`);
for(const token of ['get_patient_telemedicine_clinicians','_scheduled_at']) assert(telemedicine.includes(token),`telemedicine availability boundary missing: ${token}`);
for(const token of ['Facility access denied','it_admin','hms_facility_modules_admin_read']) assert(facilityScope.includes(token),`facility module scope boundary missing: ${token}`);
for(const token of ['hms_get_enterprise_workspace','hms_create_enterprise_record','user_active_facilities']) assert(enterpriseUi.includes(token),`enterprise workspace UI boundary missing: ${token}`);
for(const route of ['/enterprise/:moduleId','/hr-payroll','/icu','/mental-health','/social-work','/quality-compliance','/infection-control','/mortuary','/ambulance','/research-portal','/external-audit','/genomics']) assert(app.includes(route),`enterprise route missing: ${route}`);
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
