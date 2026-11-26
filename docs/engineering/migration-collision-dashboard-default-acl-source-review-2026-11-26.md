# Source interaction review: dashboard, canteen and default function privileges — 2026-11-26

## Scope

Static source inspection of five colliding migration files in two version groups:

- `20260929200000_role_dashboard_kpi_cleanup.sql`
- `20260929200000_fix_canteen_menu_rbac_realtime.sql`
- `20260929200000_secure_default_function_execute_privileges.sql`
- `20260929203000_active_dashboard_role_context.sql`
- `20260929203000_harden_security_definer_read_workspace_paths_batch6.sql`

No database was queried or modified. This review does not establish hosted deployment order.

## Object and dependency map

### Version group 20260929200000

1. **Role dashboard KPI cleanup**
   - Replaces `public.get_role_dashboard_summary()`.
   - Function is SECURITY INVOKER, uses `SET search_path = public`, requires `auth.uid()`, resolves one assigned role, and returns role-specific dashboard cards.
   - Explicitly revokes PUBLIC/anon and grants EXECUTE to authenticated.
2. **Canteen menu RBAC/realtime**
   - Alters `public.has_role(uuid, public.app_role)` search_path to `pg_catalog, public`.
   - Replaces read policies on `meal_menus`, `meal_menu_items`, and `realtime.messages`.
   - Uses `current_user_has_role('admin')` and `current_user_has_role('canteen')` in the policy predicates.
3. **Default function EXECUTE privileges**
   - Revokes default EXECUTE grants to PUBLIC, anon and authenticated for future functions created by postgres and supabase_admin in public.
   - Does not retroactively change existing function ACLs.

Git ancestry orders the role dashboard cleanup before the canteen policy update, and both before the default-privilege migration. The SQL objects are mostly distinct; the ordering is evidence, not a substitute for replay.

### Version group 20260929203000

1. **Active dashboard role context**
   - Reads the current definition of `public.get_role_dashboard_summary()` through `pg_get_functiondef(...::regprocedure)`.
   - Performs literal body substitutions to create `public.get_role_dashboard_summary_for_role(text)`.
   - Adds a server-side check that the requested role is assigned to `auth.uid()`.
   - Explicitly revokes PUBLIC/anon and grants EXECUTE to authenticated for the new overload.
2. **SECURITY DEFINER read workspace search-path hardening**
   - Alters search_path on a fixed list of existing function signatures to `pg_catalog, public`.
   - The listed signatures do not include either dashboard summary function.

Git ancestry orders the role-context migration before the search-path hardening migration. The dynamic definition transformation has a concrete prerequisite: `get_role_dashboard_summary()` must exist with the expected function body markers. This makes the `20260929200000_role_dashboard_kpi_cleanup.sql` → `20260929203000_active_dashboard_role_context.sql` dependency stronger than a filename/timestamp inference.

## Findings and unresolved risks

1. **Dynamic text replacement is brittle.** The role-context migration silently relies on exact formatting and exact text in the source function body. If the expected old function definition is absent or has drifted, `replace` can return unchanged SQL and the migration may fail later or produce an unintended function body. A precondition should assert both marker replacements occurred before EXECUTE.
2. **Dashboard data scope needs separate review.** The dashboard function is SECURITY INVOKER, so underlying RLS applies, but multiple cards count facility-sensitive rows without explicit facility predicates. Correctness and privacy therefore depend on table RLS being comprehensive for every referenced relation. This review did not prove that.
3. **Search path is not fully hardened in the dashboard function.** `get_role_dashboard_summary()` sets `search_path = public`, unlike the later batch which uses `pg_catalog, public`. The function is SECURITY INVOKER, but pinning pg_catalog first remains a reasonable hardening target after exact behavior and object references are verified.
4. **Default privileges are owner-specific.** The migration handles postgres and supabase_admin, but not other possible migration owners. It is also prospective; existing functions need their own signature-level ACL inventory. Do not infer that all public functions become inaccessible after this migration.
5. **Policy dependencies need role-function verification.** The canteen policies call `current_user_has_role`; this migration changes `has_role` rather than that function. Confirm the helper's definition, ACL, search_path, and facility semantics in the complete dependency graph.

## Safe implementation opportunities

- Add a source-level regression that the active-role migration checks for both exact replacement markers and fails closed if either is missing.
- Add a SQL contract asserting the requested role must be assigned to the authenticated user and that the overload retains explicit authenticated-only EXECUTE grants.
- Review all dashboard card relations against facility-scoped RLS and the actual service-order schema before changing query predicates.
- Inventory default ACLs by every function-owning role and compare actual per-signature grants; do not apply blanket revocations.
- Preserve the explicit Git ancestry constraints in the separate fresh-install candidate plan, but do not rename or reorder the active historical migrations.

## Disposition

The two groups have useful Git-DAG ordering evidence. The dashboard function transformation has a clear source dependency on the earlier dashboard definition. The remaining security and data-scope questions require broader source/catalog verification and disposable PostgreSQL replay. No migration files were changed and no SQL was applied.
