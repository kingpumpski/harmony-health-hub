import assert from 'node:assert/strict';
import fs from 'node:fs';

const migration=fs.readFileSync(
  'supabase/migrations/20260923175000_service_order_revoked_helper_reconciliation.sql',
  'utf8',
);

for (const fn of [
  'activate_patient_visit_coverage',
  'create_service_order',
  'cancel_service_order',
  'mark_service_order_in_progress',
  'complete_service_order',
  'get_department_queue',
]) assert.match(migration,new RegExp('CREATE OR REPLACE FUNCTION public\\.'+fn));

assert.equal(migration.includes('is_clinical_staff('),false);
assert.match(migration,/current_user_is_clinical_staff\(\)/);
assert.match(migration,/current_user_has_role\('admin'\)/);
assert.match(migration,/Active patient not found/);
assert.match(migration,/Encounter does not belong to this patient/);
console.log('service-order revoked helper reconciliation contract passed');
