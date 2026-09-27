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
console.log(`Sidebar role contract passed for ${roles.length} roles`);