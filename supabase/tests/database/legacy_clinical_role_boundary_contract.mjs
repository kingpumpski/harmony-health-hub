import fs from 'node:fs';
import assert from 'node:assert/strict';

const migration = fs.readFileSync(
  'supabase/migrations/20260928163000_harden_legacy_clinical_role_boundaries.sql',
  'utf8',
);

const expected = {
  acknowledge_vital_alert: ['admin','practitioner','nurse','midwife','specialist_nurse'],
  create_meal_plan_workflow: ['admin','practitioner','nurse','midwife','specialist_nurse','canteen'],
  get_department_queue: ['admin','accountant','practitioner','nurse','midwife','specialist_nurse','lab_technician','radiologist','radiology_technician','pharmacist'],
  get_pending_specialist_referrals: ['admin','practitioner','nurse','midwife','specialist_nurse'],
  mark_meal_order_delivered: ['admin','practitioner','nurse','midwife','specialist_nurse','canteen'],
  patient_coverage_details: ['admin','accountant','front_desk','practitioner','nurse','midwife','specialist_nurse','lab_technician','radiologist','radiology_technician','pharmacist'],
};

for (const fn of Object.keys(expected)) {
  assert.match(migration, new RegExp(`CREATE OR REPLACE FUNCTION public\\.${fn}`));
}
assert.equal(migration.includes('is_clinical_staff('), false);

for (const [fn, roles] of Object.entries(expected)) {
  const start = migration.indexOf(`CREATE OR REPLACE FUNCTION public.${fn}`);
  const next = migration.indexOf('CREATE OR REPLACE FUNCTION public.', start + 1);
  const block = migration.slice(start, next === -1 ? migration.length : next);
  for (const role of roles) {
    assert.ok(block.includes(`public.has_role(uid,'${role}')`) || block.includes(`public.has_role((SELECT auth.uid()),'${role}'::public.app_role)`), `${fn} missing ${role}`);
  }
}
for (const role of ['accountant','front_desk','canteen']) {
  const vital = migration.slice(migration.indexOf('CREATE OR REPLACE FUNCTION public.acknowledge_vital_alert'), migration.indexOf('CREATE OR REPLACE FUNCTION public.create_meal_plan_workflow'));
  assert.equal(vital.includes(`has_role(uid,'${role}')`), false);
}
for (const fn of Object.keys(expected)) {
  assert.match(migration, new RegExp(`REVOKE ALL ON FUNCTION public\\.${fn}`));
  assert.match(migration, new RegExp(`GRANT EXECUTE ON FUNCTION public\\.${fn}.*authenticated`));
}
console.log(`Legacy clinical-role boundary contract passed for ${Object.keys(expected).length} functions`);
