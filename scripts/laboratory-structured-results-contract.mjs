import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const source = readFileSync(new URL('../src/pages/Laboratory.tsx', import.meta.url), 'utf8');
const packageJson = JSON.parse(readFileSync(new URL('../package.json', import.meta.url), 'utf8'));
const structuredMigration = readFileSync(new URL('../supabase/migrations/20260930001902_structured_lab_parameter_result_workflow.sql', import.meta.url), 'utf8');
const hardeningMigration = readFileSync(new URL('../supabase/migrations/20261001095001_harden_encounter_appointment_lab_lineage.sql', import.meta.url), 'utf8');

assert.match(source, /parameters\?: Array</, 'catalogue rows must expose structured parameter definitions');
assert.match(source, /item\?\.parameters && item\.parameters\.length > 0/, 'structured test catalogue entries must render parameter inputs');
assert.match(source, /enter_lab_result_structured/, 'structured tests must use the structured result RPC');
assert.match(source, /enter_lab_result'/, 'legacy narrative/single-value tests must retain the supported result RPC');
assert.match(source, /parameter\.required && !structuredResults\[parameter\.code\]/, 'required parameters must be validated before submission');
assert.match(source, /savingResultFor/, 'result submission must prevent duplicate submissions and show progress');
assert.match(source, /orderAction/, 'sample collection and approval actions must guard duplicate clicks');
assert.match(source, /catch \(error\)[\s\S]*finally \{\s*setLoading\(false\)/, 'workspace load failures must not leave loading active');
assert.match(source, /catch \(requestError\)/, 'mutation transport rejections must be handled without unhandled promises');
assert.match(source, /setParameterValues\(\{\}\)/, 'structured values must be cleared after a successful submission');
assert.match(structuredMigration, /Required laboratory parameter is missing/, 'server must independently enforce required parameters');
assert.match(hardeningMigration, /enter_lab_result_structured/, 'structured result RPC must be included in the hardening migration');
assert.match(packageJson.scripts.test, /test:laboratory-structured-results/, 'contract must run in the required test chain');
assert.equal(packageJson.scripts['test:laboratory-structured-results'], 'node scripts/laboratory-structured-results-contract.mjs');

console.log('Laboratory structured-result contract passed.');
