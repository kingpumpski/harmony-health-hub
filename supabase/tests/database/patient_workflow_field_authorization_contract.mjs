import fs from 'node:fs';

const migration = fs.readFileSync(
  'supabase/migrations/20260929174500_patient_workflow_field_authorization.sql',
  'utf8',
);

const checks = [
  ['existing RPC signature preserved', migration.includes('update_patient_workflow(_patient_id uuid, _changes jsonb)')],
  ['existing row lock preserved', migration.includes('for update')],
  ['existing search path hardened', migration.includes('set search_path = pg_catalog, public')],
  ['unknown fields fail closed', migration.includes('Patient field is not permitted')],
  ['clinical fields protected from front desk', migration.includes("v_role = 'front_desk'") && migration.includes('blood_group')],
  ['administrative fields protected from clinical roles', migration.includes("v_role in ('nurse','practitioner','midwife')") && migration.includes('insurance_number')],
  ['city/genotype/insurance group/expiry are persisted', migration.includes('city = case') && migration.includes('genotype = case') && migration.includes('insurance_group_number = case') && migration.includes('insurance_expiry = case')],
  ['authenticated execute only', migration.includes('revoke all on function public.update_patient_workflow(uuid,jsonb) from public, anon') && migration.includes('grant execute on function public.update_patient_workflow(uuid,jsonb) to authenticated')],
];

for (const [label, ok] of checks) {
  if (!ok) throw new Error(`Patient workflow authorization contract failed: ${label}`);
}

console.log(`Patient workflow authorization contract passed: ${checks.length}/${checks.length}`);
