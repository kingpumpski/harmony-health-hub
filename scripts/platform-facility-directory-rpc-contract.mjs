import fs from 'node:fs';
import assert from 'node:assert/strict';

const migrationPath = 'supabase/migrations/20261014102730_restore_platform_facility_directory_rpc.sql';
const migration = fs.readFileSync(migrationPath, 'utf8').toLowerCase();
const page = fs.readFileSync('src/pages/admin/PlatformFacilityOnboarding.tsx', 'utf8');

for (const token of [
  'create or replace function public.platform_list_facilities()',
  'create or replace function public.platform_list_facilitys()',
  "ur.role = 'system_superuser'::public.app_role",
  'public.healthcare_facilities hf',
  "set search_path = ''",
  'revoke all on function public.platform_list_facilities() from public, anon, authenticated',
  'revoke all on function public.platform_list_facilitys() from public, anon, authenticated',
  'grant execute on function public.platform_list_facilities() to authenticated',
  'grant execute on function public.platform_list_facilitys() to authenticated',
  "notify pgrst, 'reload schema'",
]) assert(migration.includes(token), 'Facility directory migration missing security or compatibility contract: ' + token);

assert(page.includes("supabase.rpc('platform_list_facilities')"), 'Facility onboarding must use canonical facility directory RPC');
assert(page.includes("supabase.rpc('platform_list_facilitys')"), 'Facility onboarding must retain legacy RPC fallback for mixed deployment versions');
assert(page.includes("candidate.code==='PGRST202'"), 'Legacy fallback must only run when the canonical RPC is missing from PostgREST schema cache');

console.log('Platform facility directory RPC contract passed: authenticated superuser-only access, canonical RPC, legacy compatibility, and schema-cache refresh.');
