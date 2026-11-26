import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const sql = readFileSync(new URL('../supabase/tests/database/ensure_updated_at_search_path_contract.sql', import.meta.url), 'utf8');
assert.match(sql, /'?public[.]ensure_updated_at[(][)]'?::regprocedure/, 'contract must target the shared timestamp trigger function');
assert.match(sql, /proconfig/, 'contract must inspect function-level configuration');
assert.match(sql, /search_path=""/, 'contract must require an empty function search_path');
assert.match(sql, /SELECT plan[(]1[)]/, 'contract must declare its assertion plan');

console.log('[ensure-updated-at] search_path database contract source checks passed');
