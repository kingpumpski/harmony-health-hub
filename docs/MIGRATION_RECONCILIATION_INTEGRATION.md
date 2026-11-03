# Migration reconciliation integration

## Branch and safety boundary

This work is isolated on `integration/migration-reconciliation`, based on `main`. The existing `main` and `fix/missing-ai-diagnosis-schema-migration` branches are preserved. This branch is not permission to merge or apply migrations.

## Current production baseline

The baseline remains `unreconciled`. The original SQL for production versions `20260916002251` and `20260916003113` has not been recovered. Production apply is prohibited. Candidate provenance is not verified provenance.

## Changes in this integration tranche

- Make an unresolved baseline a failing validation result (exit code 2), rather than a green workflow with a warning.
- Keep production apply fail-closed (exit code 1).
- Add runtime tests for unresolved baseline, read-only verify, exact allowlist, unexpected versions, ambiguous rows, duplicate versions, and malformed allowlist entries.
- Remove the production `db push --dry-run` validation path while baseline provenance is unresolved.
- Require an exact, reviewed pending-version allowlist before any production apply step.

## Still required before declaring migration repair complete

1. Recover or independently establish authoritative evidence for the two canonical baseline entries; do not fabricate SQL.
2. Produce a per-version mapping of production ledger to repository migrations using Git history and SQL identity, including renamed files and collisions.
3. Review all 97 changed migration files and every rename/version change against deployment history.
4. Resolve SQL/function signature compatibility with actual application callers; do not change RPC return types merely to repair quoting.
5. Run delimiter, filename, dependency, and schema-contract checks.
6. Run clean replay and supported upgrade replay against a disposable local database after the Docker/Supabase local runtime is operational.
7. Run application lint, typecheck, full tests, build, and relevant GitHub Actions for the exact integration commit.
8. Obtain explicit review and approval before changing baseline status or production apply permissions.

## Prohibited actions

No production `supabase db push`, no direct edits to `supabase_migrations.schema_migrations`, no `supabase migration repair`, no fabricated baseline migrations, no `supabase db reset` against production, and no merge to `main` without explicit approval and passing required checks.
