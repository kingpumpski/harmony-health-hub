import assert from 'node:assert/strict';
import fs from 'node:fs';

const operationalPath = 'docs/engineering/migration-source-candidates/20261125_operational_workspace_facility_boundary.sql.candidate';
const billingPath = 'docs/engineering/migration-source-candidates/20261125_billing_special_form_repair.sql.candidate';
const operational = fs.readFileSync(operationalPath, 'utf8');
const billing = fs.readFileSync(billingPath, 'utf8');

for (const [name, source] of [['operational workspace', operational], ['billing', billing]]) {
  assert.match(source, /^-- REVIEW CANDIDATE ONLY\. NOT AN ACTIVE SUPABASE MIGRATION\./, name + ' repair must remain inactive until CLI generation and review');
  assert.match(source, /supabase migration new/, name + ' repair must require a CLI-generated migration identity');
  assert.match(source, /pg_get_functiondef/, name + ' repair must preserve the deployed function definition as its starting point');
  assert.match(source, /RAISE EXCEPTION/, name + ' repair must fail closed on drift');
  assert.doesNotMatch(source, /\b(?:INSERT|UPDATE|DELETE|TRUNCATE)\s+public\./i, name + ' repair must not mutate application data');
}

for (const fragment of [
  "v_platform_admin := v_role IN (''it_admin'',''system_superuser'');",
  "AND (v_platform_admin AND v_facility IS NULL OR p.facility_id=v_facility)",
  "WHERE active AND (v_platform_admin AND v_facility IS NULL OR facility_id=v_facility)",
  "WHERE v_platform_admin AND v_facility IS NULL OR b.facility_id=v_facility",
  "id=v_facility"
]){
  assert.ok(operational.includes(fragment), 'operational repair must enforce ' + fragment);
}
assert.match(operational, /REVOKE ALL ON FUNCTION public\.get_operational_workspace\(text, integer\) FROM PUBLIC, anon/i);
assert.match(operational, /GRANT EXECUTE ON FUNCTION public\.get_operational_workspace\(text, integer\) TO authenticated/i);

for (const fragment of ['pg_catalog.coalesce(', 'pg_catalog.greatest(', 'pg_catalog.least(']) {
  assert.ok(billing.includes(fragment), 'billing repair must recognize expected broken source ' + fragment);
}
for (const fragment of ['COALESCE(', 'GREATEST(', 'LEAST(']) {
  assert.ok(billing.includes(fragment), 'billing repair must restore ' + fragment);
}

console.log('Forward repair candidate contracts passed (candidate files are not active migrations).');
