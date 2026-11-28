# Development project access and CI blockers — 2026-11-24

## Confirmed development Supabase target

The user supplied the following non-secret environment identifiers:

- Project ID: `pmebpkcufyrbjhawsiyn`
- API URL: `https://pmebpkcufyrbjhawsiyn.supabase.co`

This confirms that the browser console errors previously observed against this project are development-environment errors, not evidence that the canonical project `ygqoptvezotdqhtimdkr` is missing the same objects.

## Access verification

On 2026-11-24, the connected Supabase integration was asked to perform read-only project inspection, migration listing, and Edge Function listing for `pmebpkcufyrbjhawsiyn`. All three operations returned permission denied (MCP -32600).

Consequently, the following remain unverified for the development project:

- Project health and PostgreSQL version
- Migration ledger and latest applied migration
- Presence of `get_my_permissions()`, `get_workflow_notifications(integer)`, `payroll_periods`, `facility_configuration`, and `platform_list_facilities()`
- Edge Function deployment state and logs for `admin-create-user`

No database changes, migration applications, or Edge Function deployments were attempted. The canonical project was not modified.

## Required next access step

Grant the connected Supabase account read access to project `pmebpkcufyrbjhawsiyn` (or reconnect the Supabase integration using an account that has access). Then repeat the read-only inventory before preparing any migration or function deployment.

The browser build must also use the development project's own publishable/anon key alongside its URL. Never copy a key from the canonical project, and never expose a service-role/secret key in Vite client environment variables.

## CI findings at PR head `3a8e6b158e4591f8e8f5de24c10d1742ec7da50f`

### Dependency lockfile install failure

Both Quality run #8899 and Migration contract run #2818 fail at `npm ci` before their substantive test steps. npm reports numerous package entries missing from the lockfile (including transitive packages and platform-specific esbuild packages). The root dependency declarations in `package.json` match the lockfile root dependency declarations, so this is not a simple top-level version declaration mismatch.

The lockfile must be regenerated reproducibly with the repository's pinned Node/npm toolchain, reviewed as a complete lockfile diff, and then validated with a clean `npm ci`. Do not bypass this with `npm install` in CI, disable lockfile enforcement, or update packages indiscriminately.

### Migration identity failure

The clean replay job independently reaches the migration preflight and stops on the 21 known duplicate migration-version groups. Supabase CLI setup, local database startup, replay, and post-replay schema/security checks are skipped. This remains a separate blocker; the migration validator must remain fail-closed.

## Current disposition

- PR #444 remains draft and unmerged.
- No historical migration was renamed, deleted, fabricated, or marked applied.
- No database DDL or Edge Function deployment was performed.
- Next engineering sequence: restore authorized read-only access to the development project; repair and verify the lockfile; continue per-file migration provenance reconciliation; only then run a clean local replay and compare its schema/security contracts.
