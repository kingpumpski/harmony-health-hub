import fs from 'node:fs';

const sidebar = fs.readFileSync('src/components/layout/Sidebar.tsx', 'utf8');
const roles = ['admin','practitioner','nurse','midwife','specialist_nurse','lab_technician','radiologist','radiology_technician','pharmacist','accountant','front_desk','canteen','patient','it_admin'];

for (const role of roles) {
  if (!sidebar.includes(`  ${role}:`)) throw new Error(`Sidebar navigation missing role: ${role}`);
}
if (sidebar.includes('roleNavGroups[user.role] ?? roleNavGroups.patient')) {
  throw new Error('Unsupported sidebar roles must not fall back to patient navigation');
}
if (!sidebar.includes('const unsupportedRole = !roleGroups;')) throw new Error('Sidebar must explicitly detect unsupported roles');
if (!sidebar.includes('Navigation is intentionally restricted')) throw new Error('Unsupported-role navigation must fail closed with an explicit message');
if (!sidebar.includes('roleNavGroups[user.role]')) throw new Error('Sidebar must resolve navigation from the assigned role');

const requiredLinks = [
  ["canteen", "/orders", "orders"],
  ["canteen", "/dietary-plans", "dietary_plans"],
  ["canteen", "/menu", "meal_orders"],
  ["radiology_technician", "/radiology", "radiology"],
  ["radiologist", "/radiology", "radiology"],
  ["pharmacist", "/pharmacy", "pharmacy"],
  ["lab_technician", "/laboratory", "laboratory"],
  ["it_admin", "/it-support", "it_support"],
];

for (const [role, href, permission] of requiredLinks) {
  const roleStart = sidebar.indexOf(`  ${role}:`);
  const remainder = sidebar.slice(roleStart + 3);
  const nextRoleOffset = remainder.search(/\n  [a-z_]+: \[/);
  const block = sidebar.slice(roleStart, nextRoleOffset === -1 ? sidebar.length : roleStart + 3 + nextRoleOffset);
  const canonicalItem = role === 'canteen' && href === '/orders' && permission === 'orders' && sidebar.includes("item(FileText, 'Meal Orders', '/orders', 'orders')");
  if (!canonicalItem && (!block.includes(`'${href}'`) || !block.includes(`'${permission}'`))) {
    throw new Error(`Sidebar role contract missing ${role} link ${href} with permission ${permission}`);
  }
}

const forbiddenLinks = [
  ["radiology_technician", "/clinical-results"],
  ["radiologist", "/clinical-results"],
  ["radiologist", "/lab-results"],
];

for (const [role, href] of forbiddenLinks) {
  const roleStart = sidebar.indexOf(`  ${role}:`);
  const remainder = sidebar.slice(roleStart + 3);
  const nextRoleOffset = remainder.search(/\n  [a-z_]+: \[/);
  const block = sidebar.slice(roleStart, nextRoleOffset === -1 ? sidebar.length : roleStart + 3 + nextRoleOffset);
  if (block.includes(`'${href}'`)) throw new Error(`Sidebar exposes unauthorized/unsupported link ${href} for ${role}`);
}

console.log(`Sidebar role contract passed for ${roles.length} roles`);


const capabilityLinks = [
  ["nurse", "/lab-results", "laboratory_results"],
  ["specialist_nurse", "/lab-results", "laboratory_results"],
  ["midwife", "/maternity", "maternity"],
  ["midwife", "/fertility", "fertility"],
  ["front_desk", "/registration", "registration"],
  ["front_desk", "/billing", "billing"],
  ["pharmacist", "/inventory", "inventory"],
  ["pharmacist", "/stock-alerts", "stock_alerts"],
  ["lab_technician", "/outside-lab", "outside_lab"],
  ["accountant", "/accounts-approvals", "accounts_approvals"],
  ["accountant", "/insurance-claims", "claims"],
  ["accountant", "/financial-reports", "financial_reports"],
  ["radiologist", "/notifications", "notifications"],
  ["it_admin", "/notifications", "notifications"],
  ["patient", "/telemedicine", "telemedicine"],
  ["patient", "/billing", "billing"],
];

for (const [role, href, permission] of capabilityLinks) {
  const roleStart = sidebar.indexOf(`  ${role}:`);
  const remainder = sidebar.slice(roleStart + 3);
  const nextRoleOffset = remainder.search(/\n  [a-z_]+: \[/);
  const block = sidebar.slice(roleStart, nextRoleOffset === -1 ? sidebar.length : roleStart + 3 + nextRoleOffset);
  if (!block.includes(`'${href}'`) || !block.includes(`'${permission}'`)) {
    throw new Error(`Sidebar capability missing ${role} link ${href} with permission ${permission}`);
  }
}

console.log('Sidebar capability alignment passed');


const app = fs.readFileSync('src/App.tsx', 'utf8');
const guardedRoutes = [
  ['/registration', 'registrationRoles'],
  ['/patients', 'patientRecordsRoles'],
  ['/patient-portal', 'patientPortalRoles'],
  ['/appointments', 'appointmentRoles'],
  ['/inpatient', 'inpatientRoles'],
  ['/billing', 'billingRoles'],
  ['/financial-reports', 'financialReportRoles'],
  ['/telemedicine', 'telemedicineRoles'],
  ['/fertility', 'fertilityRoles'],
  ['/outside-lab', 'outsideLabRoles'],
  ['/stock-alerts', 'pharmacyInventoryRoles'],
  ['/menu', 'canteenRoles'],
  ['/orders', 'canteenRoles'],
  ['/dietary-plans', 'canteenRoles'],
  ['/notifications', 'notificationRoles'],
  ['/notification-preferences', 'notificationRoles'],
];

for (const [href, roles] of guardedRoutes) {
  const marker = `<Route path="${href}" element={<RoleGuard allowedRoles={${roles}}}`;
  if (!app.includes(marker)) throw new Error(`Sidebar-reachable route ${href} is not guarded by ${roles}`);
}

const roleArrays = {
  registrationRoles: ['admin','front_desk'],
  patientPortalRoles: ['patient'],
  appointmentRoles: ['admin','practitioner','nurse','specialist_nurse','midwife','front_desk','patient'],
  telemedicineRoles: ['admin','practitioner','patient'],
  fertilityRoles: ['admin','practitioner','midwife'],
  outsideLabRoles: ['admin','lab_technician'],
  pharmacyInventoryRoles: ['admin','pharmacist'],
  canteenRoles: ['admin','canteen'],
  financialReportRoles: ['admin','accountant'],
  notificationRoles: ['admin','radiologist','radiology_technician','it_admin'],
};

for (const [name, roles] of Object.entries(roleArrays)) {
  const declaration = new RegExp(`const ${name} = \\[([^\\]]+)\\]`);
  const match = app.match(declaration);
  if (!match) throw new Error(`Missing route role array: ${name}`);
  for (const role of roles) if (!match[1].includes(`'${role}'`)) throw new Error(`Route role array ${name} missing ${role}`);
}

console.log('Sidebar-reachable route authorization contract passed');
