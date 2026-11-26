import fs from 'node:fs';

const read=(path)=>fs.readFileSync(path,'utf8');
const dashboard=read('src/pages/Dashboard.tsx');
const permissions=read('src/lib/permissions.ts');
const migration=read('supabase/migrations/20260926233000_role_dashboard_server_summary.sql');
const activeRoleMigration=read('supabase/migrations/20260929203000_active_dashboard_role_context.sql');
const superuserMigration=read('supabase/migrations/20261004270000_add_system_superuser_dashboard_contract.sql');
const auth=read('src/contexts/AuthContext.tsx');

if (!migration.includes('SECURITY INVOKER')) throw new Error('Dashboard summary must remain RLS-aware');
if (!auth.includes('current.roles.includes(nextRole)')) throw new Error('Active role switching must be limited to assigned roles');
if (!activeRoleMigration.includes('get_role_dashboard_summary_for_role(_requested_role text DEFAULT NULL)')) throw new Error('Validated active-role dashboard function is missing');
if (!activeRoleMigration.includes('Requested dashboard role is not assigned to the authenticated user')) throw new Error('Active dashboard role must be server-validated');
if (!activeRoleMigration.includes('REVOKE ALL ON FUNCTION public.get_role_dashboard_summary_for_role(text) FROM PUBLIC, anon')) throw new Error('Active dashboard function must not be executable anonymously');
if (!activeRoleMigration.includes('GRANT EXECUTE ON FUNCTION public.get_role_dashboard_summary_for_role(text) TO authenticated')) throw new Error('Active dashboard function must be authenticated-only');
const roles=['admin','practitioner','nurse','midwife','specialist_nurse','lab_technician','radiologist','radiology_technician','pharmacist','accountant','front_desk','canteen','patient','it_admin','system_superuser','physiotherapist','ophthalmologist','dentist','dietician'];
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
  ['system_superuser','SystemSuperuserDashboard'],
  ['physiotherapist','PhysioDashboard'],
  ['ophthalmologist','OphthalmologyDashboard'],
  ['dentist','DentistDashboard'],
  ['dietician','DieticianDashboard'],
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
for (const dashboardPath of ['src/pages/dashboard/CanteenDashboard.tsx','src/pages/dashboard/ITAdminDashboard.tsx','src/pages/dashboard/PatientDashboard.tsx']) {
  const source=read(dashboardPath);
  if (!source.includes("get_role_dashboard_summary_for_role")) throw new Error(`Active-role dashboard RPC missing in ${dashboardPath}`);
  if (!/\}\s*,\s*\[user\?\.role\]\s*\);/.test(source)) throw new Error(`Active-role dashboard loader must refresh when role changes: ${dashboardPath}`);
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
if (!superuserMigration.includes("system_superuser") || !superuserMigration.includes("Registered facilities") || !superuserMigration.includes("get_role_dashboard_summary_for_role(text)")) throw new Error('System Superuser dashboard migration contract missing');
console.log(`Role dashboard contract passed for ${roles.length} roles`);
const authSource=read('src/contexts/AuthContext.tsx');
if (!authSource.includes('activeRoleStorageKey')) throw new Error('Active role session persistence contract missing');
if (!authSource.includes('roles.includes(persistedRole)')) throw new Error('Persisted active role must be revalidated against assigned roles');
if (!authSource.includes('sessionStorage.removeItem(activeRoleStorageKey(session.user.id))')) throw new Error('Active role context must clear on logout');


const systemSuperuserDashboard = read('src/pages/dashboard/SystemSuperuserDashboard.tsx');
if (!systemSuperuserDashboard.includes("get_role_dashboard_summary_for_role")) throw new Error('System Superuser dashboard must use the validated role-scoped summary RPC');
if (!systemSuperuserDashboard.includes("_requested_role: 'system_superuser'")) throw new Error('System Superuser dashboard must request its assigned server role');

const nurse = read('src/pages/dashboard/NurseDashboard.tsx');
if (!nurse.includes("type InpatientFilter = 'all' | 'critical' | 'stable';")) throw new Error('Nursing dashboard must use the canonical inpatient filter statuses');
if (!nurse.includes("['all', 'critical', 'stable'] as const")) throw new Error('Nursing dashboard filter options must match its rendered status model');
if (nurse.includes("'attention'] as const")) throw new Error('Nursing dashboard must not expose the obsolete attention status filter');
const radiologyTechnician = read('src/pages/dashboard/RadiologyTechnicianDashboard.tsx');
if (!radiologyTechnician.includes("get_role_dashboard_summary_for_role")) throw new Error('Radiology technician dashboard must use the validated role-scoped summary RPC');
if (!radiologyTechnician.includes("[user?.role]")) throw new Error('Radiology technician dashboard must refresh when active role changes');

const dashboardRolePriority = read('src/pages/Dashboard.tsx');
if (!dashboardRolePriority.includes("const isPlatformSuperuser = user.roles.includes('system_superuser')")) throw new Error('Assigned platform superusers must be detected independently of the currently selected facility role');
if (!dashboardRolePriority.includes("const activeRole = isPlatformSuperuser ? 'system_superuser' : user.role")) throw new Error('Platform superuser dashboard must take precedence over facility role selection');
if (!dashboardRolePriority.includes("switch(String(activeRole))")) throw new Error('Dashboard routing must use the resolved platform-priority role');
if (!dashboardRolePriority.includes("user.roles.length > 1 && !isPlatformSuperuser")) throw new Error('Platform superusers must not be switched away from the platform dashboard by the facility-role selector');

if (!systemSuperuserDashboard.includes('try {') || !systemSuperuserDashboard.includes('catch (error)') || !systemSuperuserDashboard.includes('finally {') || !systemSuperuserDashboard.includes('if (!cancelled) setLoading(false)')) throw new Error('System Superuser dashboard must handle thrown RPC failures and always settle loading state');
if (!systemSuperuserDashboard.includes("console.error('[dashboard] platform summary unavailable:', error)")) throw new Error('System Superuser dashboard network failures must be diagnosable');


// Historical migration source-shape guard: the canonical service-order lifecycle
// uses status. A colliding CREATE TABLE IF NOT EXISTS migration proposes a
// different shape, which must remain an explicit replay blocker until provenance
// and deployed schema are reconciled.
const canonicalServiceOrders = read('supabase/migrations/20260911004959_e283cf8c-f6e8-4347-b4c0-689d591d33e4.sql');
const serviceOrderLifecycle = read('supabase/migrations/20260911233000_phase2_service_order_payment_gating.sql');
const serviceOrderOverride = read('supabase/migrations/20260916100000_harden_service_order_override_and_release_contract.sql');
const collidingWorkflow = read('supabase/migrations/20260912162000_hims_workflow_completion.sql');
const dashboardKpi = read('supabase/migrations/20260929200000_role_dashboard_kpi_cleanup.sql');

for (const [label, source, token] of [
  ['canonical service_orders status column', canonicalServiceOrders, 'status TEXT NOT NULL DEFAULT \'pending_payment\''],
  ['service-order lifecycle status constraint', serviceOrderLifecycle, "CHECK (status IN ('pending_payment_approval','released','in_progress','completed','cancelled'))"],
  ['override RPC canonical status use', serviceOrderOverride, "v_order.status <> 'pending_payment_approval'"],
  ['dashboard canonical status use', dashboardKpi, "FROM public.service_orders WHERE status IN ('pending_payment_approval','released','in_progress')"],
  ['colliding workflow alternate payment_status shape', collidingWorkflow, "payment_status TEXT NOT NULL DEFAULT 'pending'"],
  ['colliding workflow alternate fulfillment_status shape', collidingWorkflow, "fulfillment_status TEXT NOT NULL DEFAULT 'blocked'"],
  ['colliding workflow trigger alternate shape dependency', collidingWorkflow, 'NEW.fulfillment_status']
]) {
  if (!source.includes(token)) throw new Error(`Service-order migration source contract missing: ${label}`);
}
if (!collidingWorkflow.includes('CREATE TABLE IF NOT EXISTS public.service_orders')) {
  throw new Error('Colliding workflow migration no longer exposes its conditional service_orders definition');
}
console.log('[role-dashboard-contract] service_orders status/fulfillment migration-shape collision is explicitly guarded');

// Guard both literal transformations used to derive the active-role function.
// This detects source drift in CI; the historical SQL remains untouched.
const dashboardSourceFunction = "CREATE OR REPLACE FUNCTION public.get_role_dashboard_summary()";
const dashboardRoleFunction = "CREATE OR REPLACE FUNCTION public.get_role_dashboard_summary_for_role(_requested_role text DEFAULT NULL)";
const originalRoleLookup = "  SELECT ur.role::text INTO v_role\\n  FROM public.user_roles ur";
if (activeRoleMigration.split(dashboardSourceFunction).length !== 2) {
  throw new Error('Active-role migration must contain exactly one dashboard function definition marker');
}
if (activeRoleMigration.split(dashboardRoleFunction).length !== 2) {
  throw new Error('Active-role migration must contain exactly one dashboard role function replacement marker');
}
if (!activeRoleMigration.includes(originalRoleLookup)) {
  throw new Error('Active-role migration source lookup replacement marker drifted');
}
if (!activeRoleMigration.includes('IF _requested_role IS NOT NULL THEN')) {
  throw new Error('Active-role migration must preserve assigned-role validation');
}
console.log('[role-dashboard-contract] dynamic active-role migration source markers are pinned');
