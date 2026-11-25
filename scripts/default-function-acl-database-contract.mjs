import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const sql = readFileSync(new URL('../supabase/tests/database/default_function_acl_contract.sql', import.meta.url), 'utf8');
for (const owner of ['postgres', 'supabase_admin']) {
  assert.match(sql, new RegExp("d[.]defaclrole = '" + owner + "'::regrole"), owner + ' default ACL must be checked');
}
assert.match(sql, /pg_default_acl[\s\S]*aclexplode[\s\S]*defaclobjtype = 'f'/, 'database contract must inspect function default ACL entries');
assert.match(sql, /acl[.]privilege_type = 'EXECUTE'/, 'database contract must check EXECUTE');
assert.match(sql, /'anon'::regrole[\s\S]*'authenticated'::regrole/, 'database contract must check both exposed client roles');
assert.match(sql, /SELECT plan[(]2[)]/, 'database contract must declare its assertion plan');

console.log('[default-function-acl] database regression contract passed');
