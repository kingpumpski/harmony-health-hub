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

const getRoleBlock = (role) => {
  const roleStart = sidebar.indexOf(`  ${role}:`);
  const nextRoleMatch = sidebar.slice(roleStart + 3).match(/\n  [a-z_]+:\s*\[/);
  const nextRole = nextRoleMatch ? roleStart + 3 + nextRoleMatch.index : -1;
  return sidebar.slice(roleStart, nextRole === -1 ? sidebar.length : nextRole);
};

const requiredLinks = [
  ["canteen", "/orders", "orders"],
  ["radiology_technician", "/radiology", "radiology"],
  ["radiologist", "/radiology", "radiology"],
  ["pharmacist", "/pharmacy", "pharmacy"],
  ["lab_technician", "/laboratory", "laboratory"],
  ["it_admin", "/it-support", "it_support"],
];

for (const [role, href, permission] of requiredLinks) {
  const block = getRoleBlock(role);
  if (!block.includes(`'${href}'`) || !block.includes(`'${permission}'`)) {
    throw new Error(`Sidebar role contract missing ${role} link ${href} with permission ${permission}`);
  }
}

const forbiddenLinks = [
  ["radiology_technician", "/clinical-results"],
  ["radiologist", "/clinical-results"],
  ["radiologist", "/lab-results"],
];

for (const [role, href] of forbiddenLinks) {
  const block = getRoleBlock(role);
  if (block.includes(`'${href}'`)) throw new Error(`Sidebar exposes unauthorized/unsupported link ${href} for ${role}`);
}

console.log(`Sidebar role contract passed for ${roles.length} roles`);


const duplicateHrefPattern = /item\([^\n]+?,\s*'([^']+)'/g;

for (const role of roles) {
  const block = getRoleBlock(role);
  const hrefs = [];
  for (const match of block.matchAll(duplicateHrefPattern)) hrefs.push(match[1]);
  const duplicates = [...new Set(hrefs.filter((href, index) => hrefs.indexOf(href) !== index))];
  if (duplicates.length) throw new Error(`Sidebar role ${role} contains duplicate destinations: ${duplicates.join(', ')}`);
}

console.log('Sidebar destination uniqueness contract passed');

const capabilityLinks = [
  ["nurse", "/lab-results", "laboratory_results"],
  ["specialist_nurse", "/lab-results", "laboratory_results"],
  ["midwife", "/maternity", "maternity"],
  ["midwife", "/fertility", "fertility"],
  ["front_desk", "/registration", "registration"],
  ["front_desk", "/billing", "billing"],

  ["lab_technician", "/outside-lab", "outside_lab"],
  ["accountant", "/accounts-approvals", "accounts_approvals"],
  ["accountant", "/insurance-claims", "claims"],
  ["patient", "/telemedicine", "telemedicine"],
  ["patient", "/billing", "billing"],
];

for (const [role, href, permission] of capabilityLinks) {
  const block = getRoleBlock(role);
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
    ['/telemedicine', 'telemedicineRoles'],
  ['/fertility', 'fertilityRoles'],
  ['/outside-lab', 'outsideLabRoles'],
    ['/orders', 'canteenRoles'],
];

for (const [href, roles] of guardedRoutes) {
  const marker = `<Route path="${href}" element={<RoleGuard allowedRoles={${roles}}}>`;
  const normalizedApp = app.replace(/\s+/g, '');
  if (!normalizedApp.includes(marker.replace(/\s+/g, ''))) throw new Error(`Sidebar-reachable route ${href} is not guarded by ${roles}`);
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
