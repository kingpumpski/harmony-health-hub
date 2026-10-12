import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const source = readFileSync(new URL('../src/pages/Laboratory.tsx', import.meta.url), 'utf8');
const catalogueModal = readFileSync(new URL('../src/components/catalogue/CatalogueCreateModal.tsx', import.meta.url), 'utf8');
const facilityScopeMigration = readFileSync(new URL('../supabase/migrations/20261012160000_scope_laboratory_workspace_to_active_facility.sql', import.meta.url), 'utf8');
const catalogueParametersMigration = readFileSync(new URL('../supabase/migrations/20261012161000_create_laboratory_catalogue_parameters.sql', import.meta.url), 'utf8');
const packageJson = JSON.parse(readFileSync(new URL('../package.json', import.meta.url), 'utf8'));
const structuredMigration = readFileSync(new URL('../supabase/migrations/20260930001902_structured_lab_parameter_result_workflow.sql', import.meta.url), 'utf8');
const hardeningMigration = readFileSync(new URL('../supabase/migrations/20261001095001_harden_encounter_appointment_lab_lineage.sql', import.meta.url), 'utf8');

assert.match(source, /parameters\?: Array</, 'catalogue rows must expose structured parameter definitions');
assert.match(source, /item\?\.parameters && item\.parameters\.length > 0/, 'structured test catalogue entries must render parameter inputs');
assert.match(source, /enter_lab_result_structured/, 'structured tests must use the structured result RPC');
assert.match(source, /Object\.entries\(result\.parameter_results\)/, 'structured values must be visible in order details');
assert.match(source, /if \(!map\[r\.lab_order_id\]\)/, 'workspace must retain the newest result for each order');
assert.match(catalogueModal, /create_lab_test_catalogue_item_with_parameters/, 'catalogue creation must persist structured parameter definitions');
assert.match(catalogueModal, /JSON\.parse\(parametersJson\)/, 'catalogue parameter JSON must be parsed before submission');
assert.match(catalogueParametersMigration, /Laboratory parameter codes must be unique/, 'server must reject duplicate parameter codes');
assert.match(catalogueParametersMigration, /Laboratory parameters must be a JSON array/, 'server must validate parameter JSON shape');
assert.match(facilityScopeMigration, /AND facility_id = v_facility/, 'patient reads must be constrained to the active facility');
assert.match(facilityScopeMigration, /lo\.facility_id = v_facility/, 'laboratory orders must be constrained to the active facility');
assert.match(facilityScopeMigration, /lr\.facility_id = v_facility/, 'laboratory results must be constrained to the active facility');
assert.match(facilityScopeMigration, /Select an active facility/, 'workspace must reject missing facility context');
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
