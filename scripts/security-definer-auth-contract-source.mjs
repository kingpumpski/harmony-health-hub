import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const sql = readFileSync('supabase/tests/database/security_definer_auth_contract.sql', 'utf8');

assert.match(sql, /has_function_privilege\('anon', p\.oid, 'EXECUTE'\)/);
assert.match(sql, /has_function_privilege\('public', p\.oid, 'EXECUTE'\)/);
assert.match(sql, /p\.proconfig IS NULL[\s\S]*search_path=/i);
assert.match(sql, /has_schema_privilege\('authenticated','public','CREATE'\)/);
assert.match(sql, /has_schema_privilege\('anon','public','CREATE'\)/);
assert.match(sql, /create_lab_test_catalogue_item_with_sample_quantity[\s\S]*create_lab_test_catalogue_item_with_parameters/);
assert.match(sql, /create_ward_unit[\s\S]*current_user_facility_id[\s\S]*has_facility_access/);

console.log('[security-definer-auth-contract-source] pinned paths, no anon/public execution, schema ACL and delegated wrappers are guarded');
