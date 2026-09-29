import fs from 'node:fs';

const read = (path) => fs.readFileSync(path, 'utf8');

const dashboard = read('src/pages/Dashboard.tsx');
const permissions = read('src/lib/permissions.ts');
const sidebar = read('src/components/layout/Sidebar.tsx');
const app = read('src/App.tsx');
const summary = read('supabase/migrations/20260926233000_role_dashboard_server_summary.sql');

const roles = [
  'admin','practitioner','nurse','midwife','specialist_nurse',
  'lab_technician','radiologist','radiology_technician','pharmacist',
  'accountant','front_desk','canteen','patient','it_admin'
];

const dashboards = {
  admin: 'AdminDashboard',
  practitioner: 'PractitionerDashboard',
  nurse: 'NurseDashboard',
  midwife: 'NurseDashboard',
  specialist_nurse: 'NurseDashboard',
  lab_technician: 'LabTechDashboard',
  radiologist: 'RadiologistDashboard',
  radiology_technician: 'RadiologyTechnicianDashboard',
  pharmacist: 'PharmacyDashboard',
  accountant: 'AccountsDashboard',
  front_desk: 'FrontDeskDashboard',
  canteen: 'CanteenDashboard',
  patient: 'PatientDashboard',
  it_admin: 'ITAdminDashboard',
};

const requiredPermissions = [
  'dashboard','patients','finance','administration','it_support','registration','appointments',
  'triage','encounters','encounters_amend','clinical_operations','inpatient','ward','handover',
  'emergency','theatre','transfusion','claims','reports','report_submissions','accounts_approvals',
  'tariff_adjustments','department_queue','laboratory','laboratory_results','radiology','radiology_results',
  'pharmacy','medication_administration','billing','maternity','telemedicine','fertility','dental',
  'procedures','anesthesia','ophthalmology','ai_clinical','users','system_library','clinical_references',
  'insurance_companies','offline_sync','data_import','inpatients','meal_orders','notifications',
  'outside_lab','financial_reports','inventory','stock_alerts','patient_portal','orders','dietary_plans',
  'create_services','create_items'
];

for (const role of roles) {
  if (!permissions.includes(`  ${role}:`)) throw new Error(`Missing frontend permission profile for ${role}`);
  if (!sidebar.includes(`  ${role}:`)) throw new Error(`Missing sidebar workspace for ${role}`);
  const component = dashboards[role];
  if (!dashboard.includes(component)) throw new Error(`Dashboard component missing for ${role}: ${component}`);
  const token = role === 'nurse' || role === 'midwife' || role === 'specialist_nurse'
    ? "case'nurse':case'midwife':case'specialist_nurse':dashboard=<NurseDashboard/>;break;"
    : `case'${role}':dashboard=<${component}/>;break;`;
  if (!dashboard.includes(token)) throw new Error(`Dashboard routing missing for ${role}`);
  if (!summary.includes(role === 'nurse' || role === 'midwife' || role === 'specialist_nurse'
    ? "ELSIF v_role IN ('nurse','midwife','specialist_nurse')"
    : `v_role = '${role}'`)) throw new Error(`Server dashboard summary missing role branch for ${role}`);
}

for (const permission of requiredPermissions) {
  if (!permissions.includes(`'${permission}'`)) throw new Error(`Permission catalog missing ${permission}`);
}

for (const path of ['/dashboard','/patients','/appointments','/vitals','/clinical-operations','/inpatient','/laboratory','/radiology','/pharmacy','/billing','/insurance-claims','/reports','/notifications']) {
  if (!app.includes(`path="${path}"`)) throw new Error(`Application route missing ${path}`);
}

if (!summary.includes('SECURITY INVOKER')) throw new Error('Role dashboard summary must remain RLS-aware');
if (!summary.includes('REVOKE ALL ON FUNCTION public.get_role_dashboard_summary() FROM PUBLIC, anon')) throw new Error('Dashboard summary must revoke anonymous execution');
if (!summary.includes('GRANT EXECUTE ON FUNCTION public.get_role_dashboard_summary() TO authenticated')) throw new Error('Dashboard summary must grant authenticated execution');

console.log(`HMS dashboard operational contract passed: ${roles.length} roles, ${requiredPermissions.length} permissions, role-scoped server summary.`);
