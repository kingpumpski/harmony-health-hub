import fs from 'node:fs';

const file = 'supabase/migrations/20261127090000_fix_department_queue_facility_scope.sql';
const sql = fs.readFileSync(file, 'utf8');
const normalized = sql.toLowerCase().replace(/\s+/g, '');

if (!sql.includes('CREATE OR REPLACE FUNCTION public.get_department_queue(') ||
    !sql.includes('_department text') || !sql.includes('_limit integer DEFAULT 100')) {
  throw new Error('Department queue repair must preserve the existing RPC argument contract');
}
if (!sql.includes('RETURNS TABLE(') || !sql.includes('SECURITY DEFINER') || !sql.includes("SET search_path = ''")) {
  throw new Error('Department queue repair must preserve table return and hardened execution mode');
}
for (const token of [
  'q.facility_id=v_facility',
  'so.facility_id=v_facility',
  'p.facility_id=v_facility',
  'v_facilityisnullandnotv_platform_admin',
  "public.has_role(auth.uid(), 'it_admin')",
  "public.has_role(auth.uid(), 'system_superuser')"
]) {
  if (!normalized.includes(token.replace(/\s+/g, ''))) throw new Error('Missing department queue facility contract: ' + token);
}
if (normalized.includes("public.has_role(auth.uid(),'admin')orpublic.has_role(auth.uid(),'it_admin')")) {
  throw new Error('Facility admin must not be included in the platform-wide queue bypass');
}
for (const role of ['lab_technician','radiologist','radiology_technician','pharmacist','accountant','canteen','front_desk','nurse','specialist_nurse','midwife']) {
  if (!sql.includes("ur.role='" + role + "'") && !sql.includes("ur.role IN ('" + role)) {
    throw new Error('Department queue role contract missing: ' + role);
  }
}
if (!sql.includes('REVOKE ALL ON FUNCTION public.get_department_queue(text,integer) FROM PUBLIC, anon;') ||
    !sql.includes('GRANT EXECUTE ON FUNCTION public.get_department_queue(text,integer) TO authenticated;')) {
  throw new Error('Department queue ACL contract changed unexpectedly');
}
console.log('[department-queue-facility-repair] PASS: queue, service order, and patient are facility-bound; only explicit platform roles bypass facility scope.');
