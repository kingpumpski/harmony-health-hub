import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const sql = readFileSync(new URL('../supabase/tests/database/patient_audit_access_contract.sql', import.meta.url), 'utf8');
for (const table of ['patient_audit', 'patient_audit_log']) {
  assert.ok(sql.includes("'public." + table + "'::regclass"), 'audit contract must cover ' + table);
}
for (const privilege of ['SELECT', 'INSERT', 'UPDATE', 'DELETE']) {
  assert.ok(sql.includes("'" + privilege + "'"), 'audit contract must inspect ' + privilege);
}
assert.match(sql, /current_user_can_select_facility_record|current_user_facility_id/, 'audit log read contract must require facility context');
assert.match(sql, /SELECT plan[(]6[)]/, 'audit contract must declare all six assertions');

console.log('[patient-audit-access] database contract source checks passed');
