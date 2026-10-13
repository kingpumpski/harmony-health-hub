import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const migration = readFileSync(new URL('../supabase/migrations/20261013180000_laboratory_test_panels.sql', import.meta.url), 'utf8');
const encounter = readFileSync(new URL('../src/pages/Encounters.tsx', import.meta.url), 'utf8');
const laboratory = readFileSync(new URL('../src/pages/Laboratory.tsx', import.meta.url), 'utf8');
const results = readFileSync(new URL('../src/pages/LaboratoryResults.tsx', import.meta.url), 'utf8');
const manager = readFileSync(new URL('../src/components/laboratory/LabTestGroupsManager.tsx', import.meta.url), 'utf8');

assert.match(migration, /CREATE TABLE public\.lab_test_groups/, 'facility panel definitions must be persisted');
assert.match(migration, /CREATE TABLE public\.lab_test_group_items/, 'panels must persist ordered catalogue membership');
assert.match(migration, /ADD COLUMN group_id uuid REFERENCES public\.lab_test_groups/, 'panel parent orders must identify the group');
assert.match(migration, /ADD COLUMN parent_order_id uuid REFERENCES public\.lab_orders/, 'released panel tests must link to their parent order');
assert.match(migration, /CREATE OR REPLACE FUNCTION public\.save_laboratory_test_group/, 'panel administration must use a governed RPC');
assert.match(migration, /public\.record_system_audit\([\s\S]*'lab_test_group_created'/, 'panel create/edit/deactivate actions must be audited');
assert.match(migration, /create_lab_order_with_payment_gate\([\s\S]*panel\.default_charge/, 'panel ordering must use a single payment-gated panel tariff');
assert.match(migration, /CREATE TRIGGER expand_paid_laboratory_panel_after_release/, 'payment release must trigger test expansion');
assert.match(migration, /so\.related_entity_id=coalesce\(o\.parent_order_id,o\.id\)/, 'child tests must remain under the paid parent billing record');
assert.match(encounter, /create_encounter_lab_panel_order/, 'encounters must be able to order a panel');
assert.match(encounter, /Panels · single tariff/, 'the encounter UI must distinguish panel ordering from individual tests');
assert.match(manager, /save_laboratory_test_group/, 'the laboratory panel page must save through the audited RPC');
assert.match(manager, /Move test up|Move test down/, 'the panel editor must support test ordering');
assert.match(laboratory, /Manage laboratory panels/, 'laboratory users must be able to open panel management');
assert.match(laboratory, /Print panel report/, 'a panel must print as one report');
assert.match(results, /Panel test progress/, 'clinicians must see approved and pending sibling test states');

console.log('Laboratory panel workflow contract passed.');
