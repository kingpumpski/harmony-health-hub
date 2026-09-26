import fs from 'node:fs';

const read=(path)=>fs.readFileSync(path,'utf8');
const dashboard=read('src/pages/Dashboard.tsx');
const permissions=read('src/lib/permissions.ts');
const migration=read('supabase/migrations/20260926233000_role_dashboard_server_summary.sql');

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
for (const role of roles) {
  if (!permissions.includes(`  ${role}:`)) throw new Error(`Frontend fallback permission map missing ${role}`);
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