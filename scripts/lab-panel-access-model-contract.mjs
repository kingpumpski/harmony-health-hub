import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const migration = readFileSync(new URL('../supabase/migrations/20261015060000_reconcile_missing_laboratory_objects.sql', import.meta.url), 'utf8');
const manager = readFileSync(new URL('../src/components/laboratory/LabTestGroupsManager.tsx', import.meta.url), 'utf8');
const databaseContract = readFileSync(new URL('../supabase/tests/database/laboratory_panel_access_model_contract.sql', import.meta.url), 'utf8');

for (const table of ['lab_test_groups', 'lab_test_group_items']) {
  assert.match(migration, new RegExp('ALTER TABLE public\\.' + table + ' ENABLE ROW LEVEL SECURITY', 'i'), table + ' must keep RLS enabled');
}
assert.match(
  migration,
  /REVOKE ALL ON TABLE public\\.lab_test_groups, public\\.lab_test_group_items[\\s\\S]*?FROM PUBLIC, anon, authenticated/i,
  'panel tables must be accessible only through governed RPCs, not direct Data API grants',
);
assert.match(
  migration,
  /CREATE OR REPLACE FUNCTION public\\.get_laboratory_test_groups[\\s\\S]*?SECURITY DEFINER[\\s\\S]*?SET search_path = ''[\\s\\S]*?current_user_facility_id\\(\\)/i,
  'panel read RPC must be SECURITY DEFINER with a pinned empty search path and active-facility scope',
);
assert.match(
  migration,
  /CREATE OR REPLACE FUNCTION public\\.save_laboratory_test_group[\\s\\S]*?SECURITY DEFINER[\\s\\S]*?SET search_path = ''[\\s\\S]*?current_user_facility_id\\(\\)/i,
  'panel write RPC must be SECURITY DEFINER with a pinned empty search path and active-facility scope',
);
assert.match(manager, /rpc\\('get_laboratory_test_groups'/, 'panel UI must read through its governed RPC');
assert.match(manager, /rpc\\('save_laboratory_test_group'/, 'panel UI must write through its audited RPC');
assert.doesNotMatch(manager, /\\.from\\(['"]lab_test_groups['"]\\)|\\.from\\(['"]lab_test_group_items['"]\\)/, 'panel UI must not query protected panel tables directly');
assert.match(databaseContract, /has_table_privilege[\\s\\S]*ensure_updated_at[\\s\\S]*search_path/i, 'database contract must guard direct table grants and trigger search_path');

console.log('[lab-panel-access-model] governed RPC-only access contract passed');
