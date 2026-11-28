# Uploaded project archive provenance audit — 2026-11-28

## Artifact inspected

- Library artifact: `harmony-health-hub.zip`
- Archive size: 93,072,004 bytes
- Archive entries: 28,110
- Project-owned entries (excluding `node_modules` and Git internals): 1,740
- No database data was extracted or queried from this archive; inspection was limited to ZIP paths and selected project documentation.

## Migration inventory re-check

The archive contains 651 SQL files in `supabase/migrations/`:

- 628 distinct 14-digit version prefixes
- 21 duplicate-version groups (44 files)
- 607 versions with exactly one source file
- No invalid/unversioned SQL filename in the active migration directory
- Latest active migration version: `20261024070000`
- No file for `20260916002251_canonical_remote_schema`

This independently reconfirms the migration-collision shape already recorded in the repository's historical-source reports. The archive is an older project snapshot and does not include the later governance and repair work on PR #444.

## What the archive does contain

- `docs/PRODUCTION_MIGRATION_BASELINE.md`: a descriptive migration-tracking reconciliation note. It records a production canonical baseline and subsequent production reconciliation entries, and explicitly states that the SQL for `20260916002251_canonical_remote_schema` and `20260916003113_fix_start_imaging_order_queue_contract` had not been recovered. It also states that the remaining task is migration-tracking reconciliation rather than rebuilding or overwriting the production schema.
- `supabase-migration-list.txt`: an older CLI migration-list capture. Its historical rows largely have blank remote columns, so it is not a complete authoritative copy of the current hosted ledger.
- `supabase/production-hotfix.sql`: a production-hotfix source artifact, not a complete schema export and not a substitute for a `pg_dump --schema-only` snapshot.

## What the archive does not contain

A filename/path scan found no database dump, schema-only export, pg_dump artifact, or canonical schema export candidate. There are no root/project `.env`, `.env.local`, `.env.production`, or `.env.development` files in the project-owned archive paths. No secret values were inspected or copied.

## Consequence for baseline recovery

This ZIP is useful as a historical application/migration source snapshot, but it cannot resolve the missing canonical baseline SQL or certify the live database schema. It must not be promoted into an authoritative fresh-install bootstrap by guessing the absent objects.

The safe next input remains a complete schema-only export from the authoritative database/environment, containing schemas, tables, constraints, indexes, functions, triggers, policies, grants, and relevant extensions. It should exclude patient or other operational row data. Keep production tracking reconciliation separate from any new-environment bootstrap design.

## Safety

No active migration file was renamed, deleted, reordered, or rewritten. No migration ledger was changed. No database writes, DDL, DML, reset, or branch creation occurred.
