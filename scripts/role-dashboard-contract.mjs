import fs from 'node:fs';

const read=(path)=>fs.readFileSync(path,'utf8');
const dashboard=read('src/pages/Dashboard.tsx');
const permissions=read('src/lib/permissions.ts');
const migration=read('supabase/migrations/20260926233000_role_dashboard_server_summary.sql');
const activeRoleMigration=read('supabase/migrations/20260929203000_active_dashboard_role_context.sql');
const auth=read('src/contexts/AuthContext.tsx');

if (!migration.includes('SECURITY INVOKER')) throw new Error('Dashboard summary must remain RLS-aware');
if (!auth.includes('current.roles.includes(nextRole)')) throw new Error('Active role switching must be limited to assigned roles');
if (!activeRoleMigration.includes('get_role_dashboard_summary_for_role(_requested_role text DEFAULT NULL)')) throw new Error('Validated active-role dashboard function is missing');
if (!activeRoleMigration.includes('Requested dashboard role is not assigned to the authenticated user')) throw new Error('Active dashboard role must be server-validated');
if (!activeRoleMigration.includes('REVOKE ALL ON FUNCTION public.get_role_dashboard_summary_for_role(text) FROM PUBLIC, anon')) throw new Error('Active dashboard function must not be executable anonymously');
if (!activeRoleMigration.includes('GRANT EXECUTE ON FUNCTION public.get_role_dashboard_summary_for_role(text) TO authenticated')) throw new Error('Active dashboard function must be authenticated-only');
const roles=['admin','practitioner','nurse','midwife','specialist_nurse','lab_technician','radiologist','radiology_technician','pharmacist','accountant','front_desk','canteen','patient','it_admin'];
const expected=[
  ['admin','AdminDashboard'],
  ['practitioner','PractitionerDashboard'],
  ['nurse','NurseDashboard'],
  ['midwife','NurseDashboard'],
  ['specialist_nurse','NurseDashboard'],
  ['lab_technician','LabTechDashboard'],
  ['radiologist','RadiologistDashboard'],
  ['radiology_technician','RadiologyTechnicianDashboard'],
  ['pharmacist','PharmacyDashboard'],
  ['accountant','AccountsDashboard'],
  ['front_desk','FrontDeskDashboard'],
  ['canteen','CanteenDashboard'],
  ['patient','PatientDashboard'],
  ['it_admin','ITAdminDashboard'],
];

for (const [role,component] of expected) {
  const token=role==="nurse"||role==="midwife"||role==="specialist_nurse"
    ? "case'nurse':case'midwife':case'specialist_nurse':dashboard=<NurseDashboard/>;break;"
    : `case'${role}':dashboard=<${component}/>;break;`;
  if (!dashboard.includes(token)) throw new Error(`Dashboard routing missing for ${role}`);
}
if (dashboard.includes("if(user.role === 'it_admin') return <ITSupportWorkspace/>")) throw new Error('IT Admin must use the role dashboard route');
if (dashboard.includes("case'front_desk':default:")) throw new Error('Dashboard default must not silently absorb unknown roles');
if (!dashboard.includes("case'front_desk':dashboard=<FrontDeskDashboard/>;break;")) throw new Error('Front desk route is missing');
if (!dashboard.includes('Dashboard unavailable')) throw new Error('Unsupported roles must fail closed');
if (dashboard.includes('WorkflowSummary')) throw new Error('Global WorkflowSummary must not be duplicated above role dashboards');
if (dashboard.includes('Role command center')) throw new Error('Global role command center must not duplicate role dashboard hierarchy');
if (!dashboard.includes('aria-label="Active operational role"')) throw new Error('Multi-role dashboard needs an accessible active-role control');
const nurse=read('src/pages/dashboard/NurseDashboard.tsx');
if (!nurse.includes("useState<'all' | 'critical' | 'stable'>('all')")) throw new Error('Nurse filter state must match rendered statuses');
if (!nurse.includes("['all', 'critical', 'stable'] as const")) throw new Error('Nurse filter options must match rendered statuses');
const radiologyTechnician=read('src/pages/dashboard/RadiologyTechnicianDashboard.tsx');
if (!radiologyTechnician.includes("get_role_dashboard_summary_for_role")) throw new Error('Radiology technician dashboard must use the validated role-scoped summary');
if (!radiologyTechnician.includes("[user?.role]")) throw new Error('Radiology technician dashboard must refresh when active role changes');

for (const role of roles) {
  if (!permissions.includes(`  ${role}:`)) throw new Error(`Frontend fallback permission map missing ${role}`);
}
for (const dashboardPath of ['src/pages/dashboard/CanteenDashboard.tsx','src/pages/dashboard/ITAdminDashboard.tsx','src/pages/dashboard/PatientDashboard.tsx']) {
  const source=read(dashboardPath);
  if (!source.includes("get_role_dashboard_summary_for_role")) throw new Error(`Active-role dashboard RPC missing in ${dashboardPath}`);
  if (!source.includes("},[user?.role]);")) throw new Error(`Active-role dashboard loader must refresh when role changes: ${dashboardPath}`);
}
for (const needle of [
  "CREATE OR REPLACE FUNCTION public.get_role_dashboard_summary()",
  "IF v_role = 'patient'",
  "IF v_role = 'admin'",
  "ELSIF v_role = 'practitioner'",
  "ELSIF v_role IN ('nurse','midwife','specialist_nurse')",
  "ELSIF v_role = 'lab_technician'",
  "ELSIF v_role IN ('radiologist','radiology_technician')",
  "ELSIF v_role = 'pharmacist'",
  "ELSIF v_role = 'accountant'",
  "ELSIF v_role = 'front_desk'",
  "ELSIF v_role = 'canteen'",
  "ELSIF v_role = 'it_admin'",
  "REVOKE ALL ON FUNCTION public.get_role_dashboard_summary() FROM PUBLIC, anon",
  "GRANT EXECUTE ON FUNCTION public.get_role_dashboard_summary() TO authenticated"
]) {
  if (!migration.includes(needle)) throw new Error(`Dashboard server contract missing: ${needle}`);
}
console.log(`Role dashboard contract passed for ${roles.length} roles`);
const authSource=read('src/contexts/AuthContext.tsx');
if (!authSource.includes('activeRoleStorageKey')) throw new Error('Active role session persistence contract missing');
if (!authSource.includes('roles.includes(persistedRole)')) throw new Error('Persisted active role must be revalidated against assigned roles');
if (!authSource.includes('sessionStorage.removeItem(activeRoleStorageKey(session.user.id))')) throw new Error('Active role context must clear on logout');
