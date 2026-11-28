import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const migration = readFileSync(new URL('../supabase/migrations/20261127100800_harden_active_dashboard_role_search_path.sql', import.meta.url), 'utf8');
const source = readFileSync(new URL('../supabase/migrations/20260929203000_active_dashboard_role_context.sql', import.meta.url), 'utf8');
const baseFunction = readFileSync(new URL('../supabase/migrations/20260929200000_role_dashboard_kpi_cleanup.sql', import.meta.url), 'utf8');

assert.ok(source.includes("CREATE OR REPLACE FUNCTION public.get_role_dashboard_summary_for_role(_requested_role text DEFAULT NULL)"), 'historical migration must define the expected active-role RPC');
assert.ok(source.includes("Requested dashboard role is not assigned to the authenticated user"), 'historical source must validate requested role membership');
assert.ok(migration.includes("public.get_role_dashboard_summary_for_role(text)"), 'forward migration must target the exact RPC signature');
assert.ok(migration.includes("pg_catalog.to_regprocedure('public.get_role_dashboard_summary_for_role(text)' )") || migration.includes("pg_catalog.to_regprocedure('public.get_role_dashboard_summary_for_role(text)')"), 'forward migration must fail closed when the RPC is absent');
assert.ok(baseFunction.includes("SECURITY INVOKER") && migration.includes("p.prosecdef") && migration.includes("OR v_is_security_definer"), 'active-role RPC must remain SECURITY INVOKER');
assert.ok(migration.includes("'jsonb'::pg_catalog.regtype"), 'active-role RPC must retain its jsonb return type');
assert.ok(migration.includes("Requested dashboard role is not assigned to the authenticated user"), 'forward guard must pin the server-side role membership error');
assert.ok(migration.includes("ur.role::text = _requested_role"), 'forward guard must pin the requested-role membership predicate');
assert.ok(migration.includes("ALTER FUNCTION public.get_role_dashboard_summary_for_role(text)\n  SET search_path TO pg_catalog, public;"), 'forward repair must harden search_path with pg_catalog first');
assert.ok(migration.includes("REVOKE ALL ON FUNCTION public.get_role_dashboard_summary_for_role(text) FROM PUBLIC, anon;"), 'PUBLIC and anon must not execute the RPC');
assert.ok(migration.includes("GRANT EXECUTE ON FUNCTION public.get_role_dashboard_summary_for_role(text) TO authenticated;"), 'authenticated execution must remain explicit');
assert.ok(!/CREATE\s+(OR\s+REPLACE\s+)?FUNCTION/i.test(migration), 'repair must not replace or redefine the dashboard RPC');
console.log('[active-dashboard-role-search-path] guarded function identity, role authorization, return type and ACL contract passed');
