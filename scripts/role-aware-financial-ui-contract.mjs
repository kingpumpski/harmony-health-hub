import fs from 'node:fs';
import assert from 'node:assert/strict';

const read = (path) => fs.readFileSync(path, 'utf8');
const access = read('src/hooks/useRoleAccess.ts');
const sidebar = read('src/components/layout/Sidebar.tsx');
const dashboard = read('src/pages/dashboard/RoleOperationalDashboard.tsx');
const dashboardData = read('src/hooks/useRoleDashboardData.ts');
const app = read('src/App.tsx');
const reportsRoute = read('src/pages/FinancialReportsRoute.tsx');
const adminOverview = read('src/pages/AdminFinancialOverview.tsx');
const summaryMigration = read('supabase/migrations/20261015121000_allow_readonly_financial_overview_roles.sql');
const imaging = read('src/pages/Imaging.tsx');
const permissions = read('src/lib/permissions.ts');

assert.match(access, /canManageFinancialSettlement = isAccountOfficer/);
for (const role of ['physiotherapist', 'ophthalmologist', 'dentist', 'dietician']) {
  const line = permissions.split('\n').find((entry) => entry.startsWith(`  ${role}:`));
  assert.ok(line && !line.includes("'billing'"), `${role} must not receive financial-settlement permission`);
}
assert.match(access, /canViewFinancialOverview = isAccountOfficer \|\| isAdmin \|\| isITAdmin \|\| isSystemSuperuser/);
assert.match(sidebar, /isFinancialNavigationPath\(nav\.href\)/);
assert.match(sidebar, /roleAccess\.isAdmin \|\| roleAccess\.isITAdmin \|\| roleAccess\.isSystemSuperuser\) return nav\.href === '\/financial-reports'/);
assert.match(sidebar, /roleAccess\.isPatient \|\| roleAccess\.isFrontDesk\) return nav\.href === '\/billing'/);

assert.match(dashboard, /kpiCards=\{topKpis\.slice\(0, 4\)\}/);
assert.match(dashboard, /secondaryKpiCards=\{secondaryKpis\.slice\(0, 4\)\}/);
assert.match(dashboard, /\.slice\(0, 5\)/);
assert.match(dashboard, /actions\.slice\(0, 6\)/);
assert.match(dashboard, /payment\|invoice\|revenue\|cash collected\|billing\|claim amount\|outstanding debt/i);
assert.match(dashboard, /!hasScheduleKpi/);
assert.doesNotMatch(dashboardData, /Revenue from Pharmacy|pharmacy_pos_sales/);
assert.match(dashboardData, /Items Requiring Reorder/);

assert.match(app, /const billingRoles = \['accountant', 'front_desk', 'patient'\] as const/);
assert.match(app, /const insuranceRoles = \['accountant'\] as const/);
assert.match(app, /const accountsRoles = \['accountant', 'front_desk'\] as const/);
assert.match(app, /const billingTariffRoles = \['accountant'\] as const/);
assert.match(app, /const financialReportRoles = \['admin', 'it_admin', 'system_superuser', 'accountant'\] as const/);
assert.match(app, /path="\/financial-reports" element=\{<RoleGuard allowedRoles=\{financialReportRoles\}><FinancialReportsRoute \/><\/RoleGuard>\}/);
assert.match(reportsRoute, /user\?\.role === 'admin'.*user\?\.role === 'it_admin'.*user\?\.role === 'system_superuser'/s);
assert.match(reportsRoute, /return <AdminFinancialOverview \/>/);
assert.match(adminOverview, /get_billing_workspace_summary/);
assert.match(adminOverview, /Read-only oversight/);
assert.doesNotMatch(adminOverview, /pay_selected_invoice_items|create_insurance_claim_draft|create_walk_in_billable_service/);
assert.match(summaryMigration, /has_role\(uid, 'it_admin'::public\.app_role\)/);
assert.match(summaryMigration, /has_role\(uid, 'system_superuser'::public\.app_role\)/);
assert.match(summaryMigration, /SET search_path = ''/);
assert.match(imaging, /const paymentStatusLabel = \(order: ImagingOrder\)/);
assert.match(imaging, /key: 'paymentStatus', label: 'Payment status'/);
assert.match(imaging, /return 'Not required'/);
assert.match(imaging, /return 'Paid'/);

console.log('Role-aware financial UI contract passed.');
