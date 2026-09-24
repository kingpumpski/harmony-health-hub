import assert from 'node:assert/strict';
import fs from 'node:fs';

const migration=fs.readFileSync(
  'supabase/migrations/20260923174000_rls_revoked_helper_reconciliation.sql',
  'utf8',
);

assert.equal(migration.includes('is_clinical_staff('), false);
assert.match(migration,/current_user_is_clinical_staff\(\)/);
assert.match(migration,/current_user_has_role\('admin'\)/);
assert.match(migration,/DROP POLICY IF EXISTS imaging_orders_clinical_insert/);
assert.match(migration,/DROP POLICY IF EXISTS service_orders_staff_read/);
assert.match(migration,/DROP POLICY IF EXISTS tt_clinical_update/);
assert.match(migration,/DROP POLICY IF EXISTS va_clinical_all/);
console.log('RLS revoked helper reconciliation contract passed');
