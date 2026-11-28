import fs from 'node:fs';

const migrationPath = 'supabase/migrations/20261127100500_fix_operational_workspace_facility_scope.sql';
const sourcePath = 'supabase/migrations/20261013133000_reconcile_operational_workspace_role_resolution.sql';
const sql = fs.readFileSync(migrationPath, 'utf8');
const source = fs.readFileSync(sourcePath, 'utf8');
const normalized = sql.toLowerCase().replace(/\s+/g, '');
const sourceNormalized = source.toLowerCase().replace(/\s+/g, '');

if (!source.includes('CREATE OR REPLACE FUNCTION public.get_operational_workspace(_module text, _limit integer DEFAULT 200)')) {
  throw new Error('Expected canonical operational workspace source definition is missing');
}
if (!sql.includes("pg_get_function_identity_arguments(p.oid)='_module text, _limit integer'")) {
  throw new Error('Repair must resolve the exact existing RPC identity');
}
for (const token of [
  "v_role = ''system_superuser'' OR (v_facility IS NOT NULL AND p.facility_id=v_facility AND a.facility_id=v_facility)",
  "v_role = ''system_superuser'' OR (v_facility IS NOT NULL AND p.facility_id=v_facility)",
  "v_role = ''system_superuser'' OR (v_facility IS NOT NULL AND facility_id=v_facility)",
  "v_role = ''system_superuser'' OR (v_facility IS NOT NULL AND b.facility_id=v_facility)",
  "v_role = ''system_superuser'' OR (v_facility IS NOT NULL AND facility_id=v_facility)",
  "v_role <> ''system_superuser'' AND v_facility IS NULL"
]) {
  if (!normalized.includes(token.toLowerCase().replace(/\s+/g, ''))) {
    throw new Error('Missing operational workspace facility invariant: ' + token);
  }
}
if (!sourceNormalized.includes("(v_platform_adminandv_facilityisnullorp.facility_id=v_facility)") ||
    !sourceNormalized.includes("frompublic.ai_clinical_sessionsorderbycreated_atdesclimitv_limit") ||
    !sourceNormalized.includes("facility_idisnull")) {
  throw new Error('Source drift detected: reviewed vulnerable predicates no longer match the documented source');
}
if (!sql.includes("''ai_clinical''") || !sql.includes('replacements <> 7') || !sql.includes('replacements <> 1')) {
  throw new Error('Repair must fail closed when expected source replacement counts drift');
}
if (!sql.includes('REVOKE ALL ON FUNCTION public.get_operational_workspace(text,integer) FROM PUBLIC, anon;') ||
    !sql.includes('GRANT EXECUTE ON FUNCTION public.get_operational_workspace(text,integer) TO authenticated;')) {
  throw new Error('Operational workspace RPC ACL contract changed');
}
console.log('[operational-workspace-facility-repair] PASS: facility admins and ordinary staff are facility-scoped; only system_superuser bypasses; legacy NULL-facility rows are excluded.');
