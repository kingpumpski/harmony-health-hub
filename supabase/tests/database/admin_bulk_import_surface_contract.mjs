// Static regression contract for the admin bulk-import authorization boundary.
import fs from 'node:fs';

const p = fs.readFileSync('supabase/functions/admin-bulk-import/index.ts', 'utf8');

const checks = [
  ['admin guard remains', p.includes('requireAdmin')],
  ['supported import entities remain explicit', p.includes("new Set(['patients', 'pharmacy_inventory', 'icd_codes'])")],
  ['legacy bulk user action removed', !p.includes("action === 'bulk_create_users'")],
  ['bulk user provisioning helper removed', !p.includes('provisionAdminUser')],
  ['user-row limit removed', !p.includes('MAX_USER_ROWS')],
  ['service role is not used for frontend authorization', p.includes('requireAdmin(service, token)')],
];

for (const [name, ok] of checks) {
  if (!ok) throw new Error('Admin bulk-import contract failed: ' + name);
}

console.log('Admin bulk-import surface contract passed');
