import fs from 'node:fs';
import assert from 'node:assert/strict';

const sidebar = fs.readFileSync('src/components/layout/Sidebar.tsx', 'utf8');
const dashboard = fs.readFileSync('src/pages/Dashboard.tsx', 'utf8');
const frontDesk = fs.readFileSync('src/pages/dashboard/FrontDeskDashboard.tsx', 'utf8');

assert.doesNotMatch(sidebar, /user\.role === 'it_admin' \? 'admin' : user\.role/);
assert.match(sidebar, /const navigationRole = user\.role;/);
assert.match(sidebar, /const secondaryPermissions = new Set<Permission>/);
assert.match(sidebar, /<span>More<\/span>/);
assert.match(sidebar, /clinical_references/);
assert.match(sidebar, /system_settings/);
assert.doesNotMatch(dashboard, /OperationalHandoffPanel/);

assert.doesNotMatch(frontDesk, /import Appointments from '@\/pages\/Appointments'/);
for (const route of ['/registration', '/appointments', '/patients', '/department-queue', '/billing']) {
  assert.match(frontDesk, new RegExp(route.replace('/', '\\/')));
}

console.log('Role-focused navigation and dashboard contract passed.');
