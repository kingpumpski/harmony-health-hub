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
  const nextRole = sidebar.indexOf('\n  ', roleStart + 3);
  const block = sidebar.slice(roleStart, nextRole === -1 ? sidebar.length : nextRole);
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
  const roleStart = sidebar.indexOf(`  ${role}:`);
  const nextRole = sidebar.indexOf('\n  ', roleStart + 3);
  const block = sidebar.slice(roleStart, nextRole === -1 ? sidebar.length : nextRole);
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
  const nextRole = sidebar.indexOf('\n  ', roleStart + 3);
  const block = sidebar.slice(roleStart, nextRole === -1 ? sidebar.length : nextRole);
  if (!block.includes(`'${href}'`) || !block.includes(`'${permission}'`)) {
    throw new Error(`Sidebar capability missing ${role} link ${href} with permission ${permission}`);
  }
}

console.log('Sidebar capability alignment passed');
