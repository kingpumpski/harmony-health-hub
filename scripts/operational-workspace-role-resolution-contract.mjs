import assert from 'node:assert/strict';
import fs from 'node:fs';

const migration = fs.readFileSync('supabase/migrations/20261013133000_reconcile_operational_workspace_role_resolution.sql', 'utf8');
const lower = migration.toLowerCase();
const roleResolution = migration.slice(migration.indexOf('SELECT CASE'), migration.indexOf('END INTO v_role;'));

for (const role of ['system_superuser', 'admin', 'it_admin', 'practitioner', 'nurse', 'midwife', 'specialist_nurse', 'front_desk', 'accountant', 'radiologist']) {
  assert.ok(roleResolution.includes("'" + role + "'::public.app_role"), 'Operational workspace role resolution must include ' + role);
}
assert.ok(roleResolution.includes("_module = 'appointments' AND public.has_role(auth.uid(), 'front_desk'::public.app_role)"), 'Front-desk role resolution must be selected for appointments before lower-priority clinical roles');
assert.ok(roleResolution.includes("_module = 'insurance' AND public.has_role(auth.uid(), 'accountant'::public.app_role)"), 'Accountant role resolution must be selected for insurance before lower-priority clinical roles');
assert.ok(roleResolution.includes("_module = 'ai_clinical' AND public.has_role(auth.uid(), 'radiologist'::public.app_role)"), 'Radiologist role resolution must be selected for AI clinical before lower-priority clinical roles');
assert.ok(lower.includes('if auth.uid() is null then raise exception'), 'RPC must reject unauthenticated calls');
assert.ok(lower.includes("set search_path to ''"), 'SECURITY DEFINER RPC must pin an empty search_path');
assert.ok(lower.includes("if not v_platform_admin and v_role not in ('admin','practitioner','nurse','midwife','specialist_nurse','front_desk')"), 'Appointment access gate must remain role-scoped');
assert.ok(lower.includes("if not v_platform_admin and v_role <> 'accountant'"), 'Insurance access gate must remain role-scoped');
assert.ok(lower.includes("if not v_platform_admin and v_role not in ('admin','practitioner','nurse','midwife','specialist_nurse','radiologist')"), 'AI clinical access gate must remain role-scoped');
assert.ok(lower.includes('revoke all on function public.get_operational_workspace(text, integer) from public, anon'), 'Anonymous/public execute must remain revoked');
assert.ok(lower.includes('grant execute on function public.get_operational_workspace(text, integer) to authenticated'), 'Authenticated RPC access must remain explicit');
console.log('Operational workspace role resolution contract passed');
