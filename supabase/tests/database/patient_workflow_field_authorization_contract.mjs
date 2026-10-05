import fs from 'node:fs';

const migration = fs.readFileSync(
  'supabase/migrations/20261005102000_harden_patient_workflow_admin_roles.sql',
  'utf8',
);

const checks = [
  ['canonical RPC signature preserved', migration.includes('update_patient_workflow(_patient_id uuid, _changes jsonb)')],
  ['row lock preserved', migration.includes('for update')],
  ['empty search path preserved', migration.includes("set search_path = ''")],
  ['Admin, IT Admin and System Superuser are privileged', migration.includes("public.has_role(uid,'admin')") && migration.includes("public.has_role(uid,'it_admin')") && migration.includes("public.has_role(uid,'system_superuser')")],
  ['multi-role authorization is not reduced to the latest role row', migration.includes('v_is_privileged_admin') && migration.includes('v_is_clinical') && migration.includes('v_is_front_desk')],
  ['privileged administrators can edit clinical and administrative fields', migration.includes('not v_is_privileged_admin and v_is_front_desk') && migration.includes('not v_is_privileged_admin and v_is_clinical')],
  ['facility/test-mode boundary remains authoritative', migration.includes('assert_patient_facility_context(v_patient.id)')],
  ['unresolved patient attribution remains blocked', migration.includes('Patient facility attribution is unresolved')],
  ['unknown fields fail closed', migration.includes('Patient field is not permitted')],
  ['authenticated execute only', migration.includes('revoke all on function public.update_patient_workflow(uuid,jsonb) from public, anon') && migration.includes('grant execute on function public.update_patient_workflow(uuid,jsonb) to authenticated')],
];

for (const [label, ok] of checks) {
  if (!ok) throw new Error(`Patient workflow admin-role contract failed: ${label}`);
}

console.log(`Patient workflow admin-role contract passed: ${checks.length}/${checks.length}`);
