import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const sql = readFileSync(new URL('../supabase/tests/database/patient_audit_access_contract.sql', import.meta.url), 'utf8');
for (const table of ['patient_audit', 'patient_audit_log']) {
  assert.ok(sql.includes("'public." + table + "'::regclass"), 'audit contract must cover ' + table);
}
for (const privilege of ['SELECT', 'INSERT', 'UPDATE', 'DELETE']) {
  assert.ok(sql.includes("'" + privilege + "'"), 'audit contract must inspect ' + privilege);
}
assert.match(sql, /current_user_facility_id/, 'audit log read contract must require active facility context');
assert.match(sql, /ILIKE '%patients%'/, 'audit log read contract must join patient lineage');
assert.match(sql, /ILIKE '%exists%'/, 'audit log read contract must require an existing patient row');
assert.match(sql, /SELECT plan[(]9[)]/, 'audit contract must declare all nine assertions');
assert.match(sql, /NOT has_table_privilege\('authenticated','public.patient_audit','SELECT'\)/, 'legacy patient snapshots must not be directly readable by authenticated clients');
assert.match(sql, /patient_audit_log_active_facility_read/, 'audit log access must use the active-facility policy');
assert.match(sql, /old_record, new_record/, 'audit trigger privacy contract must be present');

assert.match(sql, /patient_audit_patient_id_fkey/);
assert.match(sql, /confdeltype='n'/);

console.log('[patient-audit-access] database contract source checks passed');
