import fs from 'node:fs';
import assert from 'node:assert/strict';
const source=fs.readFileSync('supabase/functions/ai-clinical-assist/index.ts','utf8');
const migration=fs.readFileSync('supabase/migrations/20261007152000_canonical_authenticated_role_resolver.sql','utf8');
assert.ok(source.includes("supabase.rpc('get_current_user_roles')"));
assert.ok(!source.includes("supabase.from('user_roles').select('role').eq('user_id', callerId)"));
assert.ok(migration.includes('CREATE OR REPLACE FUNCTION public.get_current_user_roles()'));
assert.ok(migration.includes('SECURITY DEFINER'));
assert.ok(migration.includes('GRANT EXECUTE ON FUNCTION public.get_current_user_roles() TO authenticated'));
console.log('AI clinical assistant canonical role resolution contract passed');

assert.ok(source.includes('let protocolCaseCount = 0;'));
assert.ok(source.includes('protocolCaseCount = cases.length;'));
assert.ok(source.includes('_case_count: protocolCaseCount,'));
assert.ok(!source.includes('_case_count: cases?.length ?? 0'), 'Protocol draft creation must not reference branch-scoped case data outside its declaration scope');
