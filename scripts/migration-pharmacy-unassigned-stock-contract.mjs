import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const historical = readFileSync(new URL('../supabase/migrations/20261002132500_pharmacy_global_category_edit.sql', import.meta.url), 'utf8');
const scopedWorkspace = readFileSync(new URL('../supabase/migrations/20261127100300_fix_pharmacy_workspace_admin_facility_scope.sql', import.meta.url), 'utf8');
const migration = readFileSync(new URL('../supabase/migrations/20261127100900_restrict_unassigned_pharmacy_stock_to_platform_superuser.sql', import.meta.url), 'utf8');

assert.ok(historical.includes("public.has_role(uid, 'admin') OR public.has_role(uid, 'system_superuser')"), 'historical reconciliation RPC must remain pinned as provenance evidence');
assert.ok(historical.includes("length(pg_catalog.btrim(coalesce(_reason, ''))) < 10"), 'legacy assignment must retain a meaningful audit reason');
assert.ok(scopedWorkspace.includes("CASE WHEN v_admin OR v_superuser THEN COALESCE(("), 'prior forward workspace repair must expose the unassigned-stock role gate');
assert.ok(migration.includes("'public.get_pharmacy_workspace(integer)'::pg_catalog.regprocedure"), 'migration must resolve the exact workspace RPC');
assert.ok(migration.includes("'public.assign_unattributed_pharmacy_inventory(uuid,text)'::pg_catalog.regprocedure"), 'migration must resolve the exact stock-assignment RPC');
assert.ok(migration.includes("v_workspace_marker text := 'CASE WHEN v_admin OR v_superuser THEN COALESCE(('"), 'migration must identify the exact unassigned-stock projection');
assert.ok(migration.includes("CASE WHEN v_superuser THEN COALESCE(("), 'only platform superusers may inspect unassigned legacy stock');
assert.ok(migration.includes("v_assign_marker text := 'IF uid IS NULL OR NOT (public.has_role(uid, ''admin'') OR public.has_role(uid, ''system_superuser'')) THEN'"), 'migration must identify the exact legacy assignment role gate');
assert.ok(migration.includes("IF uid IS NULL OR NOT public.has_role(uid, ''system_superuser'') THEN"), 'only platform superusers may assign stock without facility attribution');
assert.ok(migration.includes("v_count <> 1"), 'unexpected function source drift must abort');
assert.ok(migration.includes("p.prosecdef") && migration.includes("v_workspace_definer") && migration.includes("v_assign_definer"), 'both functions must remain SECURITY DEFINER');
assert.ok(migration.includes("search_path=\"\"") && migration.includes("v_workspace_empty_path") && migration.includes("v_assign_empty_path"), 'both functions must retain an empty search_path');
assert.ok(migration.includes("REVOKE ALL ON FUNCTION public.get_pharmacy_workspace(integer) FROM PUBLIC, anon;"), 'workspace execution must remain restricted');
assert.ok(migration.includes("REVOKE ALL ON FUNCTION public.assign_unattributed_pharmacy_inventory(uuid,text) FROM PUBLIC, anon;"), 'assignment execution must remain restricted');
assert.ok(!/CREATE\s+(OR\s+REPLACE\s+)?FUNCTION/i.test(migration), 'migration must replace exact existing definitions, not invent new RPCs');
console.log('[pharmacy-unassigned-stock] only system_superuser can inspect or assign facility-unattributed legacy stock');
