import fs from 'node:fs';

const file = 'supabase/migrations/20261126154500_fix_pharmacy_workspace_admin_facility_scope.sql';
const sql = fs.readFileSync(file, 'utf8');
const normalized = sql.toLowerCase().replace(/\s+/g, '');

if (!sql.includes('CREATE OR REPLACE FUNCTION public.get_pharmacy_workspace(_limit integer DEFAULT 200)')) {
  throw new Error('Forward repair must preserve get_pharmacy_workspace(integer) signature');
}
if (!sql.includes("RETURNS jsonb") || !sql.includes('STABLE') || !sql.includes('SECURITY DEFINER') || !sql.includes("SET search_path = ''")) {
  throw new Error('Forward repair must preserve return type, volatility, SECURITY DEFINER, and empty search_path');
}
for (const predicate of [
  'andv_facilityisnotnullandp.facility_id=v_facility',
  'andv_facilityisnotnullandd.facility_id=v_facility',
  'andp.facility_id=v_facility'
]) {
  if (!normalized.includes(predicate)) throw new Error('Missing active-facility predicate: ' + predicate);
}
if (normalized.includes('v_adminor(v_facilityisnotnullandp.facility_id=v_facility)') ||
    normalized.includes('v_adminor(v_facilityisnotnullandd.facility_id=v_facility)')) {
  throw new Error('Facility admin must not bypass pharmacy patient or dispensing-plan facility predicates');
}
for (const role of ["public.has_role(v_uid, 'admin')", "public.has_role(v_uid, 'pharmacist')", "public.has_role(v_uid, 'front_desk')"]) {
  if (!sql.includes(role)) throw new Error('Forward repair unexpectedly removed existing role checks: ' + role);
}
if (!sql.includes('REVOKE ALL ON FUNCTION public.get_pharmacy_workspace(integer) FROM PUBLIC, anon;') ||
    !sql.includes('GRANT EXECUTE ON FUNCTION public.get_pharmacy_workspace(integer) TO authenticated;')) {
  throw new Error('Forward repair must preserve the explicit function ACL contract');
}
console.log('[pharmacy-workspace-facility-repair] PASS: admin reads are facility-scoped; function signature, role checks, security mode, and ACL are preserved.');
