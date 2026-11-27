# Active-role dashboard RPC hardening — 2026-11-27

## Finding

The historical active-role migration derives `get_role_dashboard_summary_for_role(text)` by applying literal replacements to `pg_get_functiondef(get_role_dashboard_summary())`. Its source contract validates assigned roles and explicitly grants execution only to `authenticated`, but the derived function inherits `SET search_path = public` from the source dashboard function.

## Forward repair

Added `20261127100800_harden_active_dashboard_role_search_path.sql`:

- Resolves the exact existing RPC signature and fails if it is absent.
- Verifies that the function remains `SECURITY INVOKER`, returns `jsonb`, and contains the reviewed server-side assigned-role check.
- Sets the function search path to `pg_catalog, public`.
- Reasserts that `PUBLIC` and `anon` cannot execute it and that `authenticated` has explicit execution permission.
- Does not redefine the RPC or change its role-selection and dashboard-card behavior.

## Static contract

Added `scripts/active-dashboard-role-search-path-contract.mjs` to `npm run test:migration-parity` and the migration workflow path filters. It pins the exact function identity, role membership guard, return type, invoker mode, search path, and ACL statements.

## Verification boundary

This is a repository-level forward repair. CI must run the new static contract. No database was accessed or modified, and the migration has not been applied. The duplicate historical migration identity groups still prevent clean PostgreSQL replay, so effective catalog settings and RPC execution remain unverified.
