import assert from 'node:assert/strict';
import fs from 'node:fs';

const path = 'supabase/migrations/20261123090000_harden_laboratory_panel_table_privileges_and_timestamp_trigger.sql';
const sql = fs.readFileSync(path, 'utf8');

assert.match(sql, /REVOKE\s+ALL\s+PRIVILEGES\s+ON\s+TABLE\s+public\.lab_test_groups\s*,\s*public\.lab_test_group_items\s+FROM\s+PUBLIC\s*,\s*anon\s*,\s*authenticated\s*;/is,
  'laboratory panel tables must not grant direct privileges to PUBLIC, anon, or authenticated');
assert.match(sql, /ALTER\s+FUNCTION\s+public\.ensure_updated_at\(\)\s+SET\s+search_path\s*=\s*''\s*;/i,
  'ensure_updated_at must use an empty fixed search_path');
assert.doesNotMatch(sql, /GRANT\s+.*\b(anon|authenticated|PUBLIC)\b/i,
  'the correction must not reintroduce direct client privileges');
console.log('[laboratory-panel-privilege-migration-contract] targeted revocation and fixed search_path assertions passed');
