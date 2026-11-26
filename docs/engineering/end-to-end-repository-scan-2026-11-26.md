# End-to-end repository scan and engineering checkpoint — 2026-11-26

## Scope and method

This is a static repository scan of the PR branch after reconciling it with the current `main` tree. It inventories repository files, migration identities, package scripts, workflow references and selected security/deployment code. It is not a runtime build, a clean database replay, a live security test, or a production readiness certification.

## Repository inventory

- 1,336 tracked files were visible in the recursive Git tree at scan time.
- 653 SQL migration files exist under `supabase/migrations/`.
- Those files contain 630 distinct 14-digit version identifiers.
- 21 version groups are duplicated, affecting 44 migration files.
- 114 database contract/test files were present in the initial inventory.
- The package manifest contains over 140 scripts after the current test-gate additions.
- The package and three inspected workflows had no missing referenced Node scripts or SQL contract files at scan time.
- Only `.env.example` was found among tracked root/nested `.env*` files; no tracked live `.env` file was found.

The duplicate timestamp groups and their file identities remain listed in the existing migration collision audit documents. They are not automatically renamed, deleted, reordered, or marked applied.

## High-priority findings and changes

### 1. Automatic production SQL execution — contained

The previous `.github/workflows/supabase-database.yml` ran an enum alteration and then executed `supabase/production-hotfix.sql` automatically on a push to `main`. The SQL file combines function replacements, data backfill, permission tables and role grants. It has not passed a clean replay or the current facility/security contract suite.

Changes made:

- Archived the exact original SQL bytes as `docs/engineering/migration-source-candidates/production-hotfix.sql.candidate`.
- Removed the executable `supabase/production-hotfix.sql` path.
- Replaced the push-triggered database workflow with a manually dispatched, review-only workflow that has no Supabase credentials, project link or SQL execution.
- Added `scripts/production-hotfix-safety-contract.mjs` and wired it into npm and quality gates.

The archived SQL is not a migration and must not be deployed without function-by-function security, facility-lineage, schema and data-backfill review.

### 2. SECURITY DEFINER search_path audit false-negative — corrected, execution pending

The prior `scripts/security-best-practices-audit.mjs` used over-escaped whitespace patterns in its SQL function scanner. Those patterns could miss ordinary SQL declarations and therefore fail to inspect the intended SECURITY DEFINER definitions.

Changes made:

- Repaired the SQL whitespace and function-declaration patterns.
- Made the audit callable against an isolated fixture root.
- Added regression fixtures for missing search_path, inline search_path, a later ALTER FUNCTION search_path, deprecated `auth.role()`, and user-metadata authorization in policies.
- Added the regression to the existing security audit npm command.

The corrected audit has not yet been run against the complete repository in a Node environment. Its output must be reviewed; any newly surfaced functions need controlled remediation rather than blanket ACL changes.

### 3. Production migration workflow — stronger deployment guardrails

Changes made:

- Added the `production` GitHub Environment to the linked database workflow.
- Removed the hardcoded project reference and now require `vars.SUPABASE_PROJECT_REF`.
- Validate the project reference before linking.
- Retained the explicit production apply confirmation and migration dry-run preflight.
- Added workflow regression assertions.

Repository configuration still needs an administrator to configure required reviewers and environment-scoped secrets/variables. This repository change alone cannot prove that GitHub environment protection is configured.

### 4. Branch divergence — reconciled

The PR branch was behind `main`. A tree-level comparison found three overlapping paths: `package.json`, `src/integrations/supabase/types.ts`, and `src/lib/oauth-return-path.ts`.

- Non-overlapping changes from main were merged through a two-parent merge commit.
- `package.json` retained the branch's migration/security test gates and incorporated main's bulk-import regression test.
- The branch's generated Supabase types were retained because they describe substantially more schema objects (156 tables versus 49 in main at scan time). Replacing them with the shorter main file would have discarded type coverage.
- The branch's OAuth return-path validation was retained; it rejects backslashes and ASCII control characters before accepting a same-origin path.

The merge commit made the PR branch zero commits behind main at that point. The latest PR state must be checked again after subsequent commits and CI.

## Migration history — still a release blocker

- The 21 duplicate version groups prevent a clean, unambiguous replay.
- The canonical hosted project previously showed 417 migration ledger entries, with historical source/ledger discrepancies including missing repository source for some hosted versions.
- Existing reports document missing historical migrations and unmatched hosted entries.
- No migration identities were rewritten, no ledger rows were inserted/deleted, and no production SQL was applied.

The next correct action is provenance recovery: preserve originals, fingerprint each colliding SQL file, compare with the hosted ledger and live catalog, identify which object definitions are already deployed, and construct a separate clean-install bootstrap strategy. A timestamp collision is not permission to choose one file arbitrarily.

## Remaining work in priority order

1. Run npm CI, typecheck, lint, production build and the corrected security audit on the reconciled branch.
2. Resolve the 21 migration collisions and historical source gaps through evidence-based provenance.
3. Rebuild the clean-install migration chain and prove full PostgreSQL 17 replay.
4. Prepare CLI-generated forward migrations for operational workspace facility isolation, billing special-form qualification, nursing handover and the remaining verified schema/security findings.
5. Run database contracts against a non-production PostgreSQL environment, then compare exact schema/function/ACL/RLS state to the canonical hosted project using read-only inspection.
6. Complete application end-to-end tests, deployment checks and role-by-role operational acceptance.

## Change safety statement

This checkpoint involved repository-only edits. It did not create a billable Supabase branch, link to the hosted project, execute SQL against Supabase, alter the migration ledger, change Auth settings, or modify patient/operational data.

## Verification status

- Static tree inventory and path-reference scan: completed.
- Production hotfix execution path: disabled and guarded by source contract.
- Security audit scanner: corrected and regression fixture added; runtime execution pending.
- Package scripts, typecheck, lint and production build: not executed in this environment.
- PostgreSQL 17 clean replay: not executed.
- Live database contracts: not executed.
- Production deployment: not performed.

**Readiness: not approved for operational use.** The repository remains blocked on migration provenance, clean replay, executed security/application tests and deployment acceptance.

### 5. MCP integration pointed at the unowned development project — corrected

The newly merged MCP Edge Function had an embedded fallback project reference and publishable key for the platform-provisioned development project. The source also allowed Vite build-time fallbacks to populate server connection settings.

Changes made:

- Removed the development project URL and embedded key from the generated Edge Function.
- Changed MCP server issuer configuration to derive its auth issuer from the same required `SUPABASE_URL` used by the user-scoped database client.
- Changed server-side Supabase client configuration to require `SUPABASE_URL` and `SUPABASE_ANON_KEY` from the Edge Function environment.
- Retained the verified OAuth user token for PostgREST calls; the MCP read tools do not use a service-role key.
- Added `scripts/mcp-project-config-contract.mjs` and included it in npm and quality gates.

The MCP Edge Function now fails closed when its environment is missing rather than silently connecting to the unowned dev project. A deploy still requires an operator to configure the correct project environment variables.

### 6. Bulk-import regression contract drift — reconciled

The merged bulk-import Edge Function uses a caller-JWT Supabase client named `db`, while an existing repository contract expected a variable named `authClient`. The contract was therefore inconsistent with the implementation.

Changes made:

- Updated the contract to require the actual caller-JWT client and its RPC calls for patient, pharmacy and ICD imports.
- Added an assertion that the service-role client is not used for direct patient, inventory or ICD table inserts.
- Kept service-role access limited to administrator verification and import audit persistence.

The bulk-import regression test and the broader application suite still need CI execution.
