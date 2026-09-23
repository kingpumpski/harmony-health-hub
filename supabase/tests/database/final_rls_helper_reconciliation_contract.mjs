import assert from 'node:assert/strict';
import fs from 'node:fs';

const s=fs.readFileSync('supabase/migrations/20260923180000_final_rls_helper_reconciliation.sql','utf8');
assert.equal(s.includes('is_clinical_staff('),false);
assert.match(s,/current_user_is_clinical_staff\(\)/);
assert.match(s,/current_user_has_role\('admin'\)/);
assert.match(s,/DROP POLICY IF EXISTS billing_overrides_staff_read/);
assert.match(s,/DROP POLICY IF EXISTS imaging_orders_clinical_insert/);
assert.match(s,/DROP POLICY IF EXISTS lab_orders_clinical_read/);
assert.match(s,/DROP POLICY IF EXISTS staff_read_visit_authorizations/);
assert.match(s,/DROP POLICY IF EXISTS va_clinical_all/);
console.log('final RLS helper reconciliation contract passed');
