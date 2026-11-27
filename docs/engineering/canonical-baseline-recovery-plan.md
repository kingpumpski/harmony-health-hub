# Canonical baseline recovery and fresh-environment bootstrap plan

Updated: 2026-11-23

## Decision

Do not fabricate or backdate a replacement for production migration `20260916002251_canonical_remote_schema` or `20260916003113_fix_start_imaging_order_queue_contract`. Their original SQL has not been recovered, and the production migration ledger is evidence of historical application, not a source from which those SQL bodies can be inferred.

The project can still pursue a **new-environment bootstrap baseline**, but it must be a separately named, explicitly versioned artifact generated from a complete, reviewed schema-only export of the current authoritative database. It must not impersonate the September 16 historical migration, and it must not be inserted into or used to rewrite the production ledger.

## Read-only source inventory captured 2026-11-23

Linked Supabase project: `ygqoptvezotdqhtimdkr` (PostgreSQL 17.6.1.166; status ACTIVE_HEALTHY).

- Hosted migration ledger: 417 entries.
- Earliest ledger entry: `20260916002251 canonical_remote_schema`.
- Second ledger entry: `20260916003113 fix_start_imaging_order_queue_contract`.
- Latest ledger entry: `20261026141054 reconcile_lab_catalogue_sample_quantity_rpc`.
- Public schema catalog counts: 156 tables, 341 functions, 452 policies, 206 non-internal triggers, 5 installed extensions, and 0 public views.

The catalog counts were obtained using read-only catalog queries. The table/column inventory was also read-only. These counts are a scope indicator only; they are **not** a schema dump and do not capture all SQL definitions, grants, constraints, indexes, types, sequences, extension configuration, storage/auth configuration, or data dependencies.

## Recovery order

1. Preserve any exact original source found in the pre-Supabase development environment, local Git history, old ZIP/archive, deployment artifact, CI artifact, or database backup. Record its origin, timestamp, SHA-256, and the exact migration version/name it belongs to.
2. Recover the two missing September migration SQL files byte-for-byte where possible. Do not synthesize them from the current live schema.
3. Recover the five missing late-October source migrations independently. Two existing inactive HR/inpatient candidates remain provenance candidates only; the three lab candidates remain unverified.
4. Build a complete schema-only export from the authoritative live database using a supported PostgreSQL/Supabase dump process, with a documented inclusion/exclusion policy. Do not include patient data, credentials, secrets, auth users, storage objects, or production data.
5. Review and normalize that export for a **fresh database bootstrap**. Include required schemas, extensions, enums/domains, tables, constraints, indexes, sequences/identity, functions/procedures, triggers, RLS enablement and policies, grants/default privileges, and required Supabase-specific dependencies. Explicitly separate managed Supabase platform objects from application-owned objects.
6. Store the generated bootstrap as a new baseline artifact with provenance metadata and a new version later than the current hosted ledger boundary. Never reuse either missing historical version.
7. Replay that bootstrap on a disposable empty Supabase/PostgreSQL 17 environment, then run all SQL contracts, generated-type checks, and application integration tests. Compare resulting schema fingerprints and object definitions against the source environment.
8. Separately design the upgrade path for already-running environments. Do not apply a fresh bootstrap over production or attempt to reset production to match it.
9. Resolve the 21 duplicate historical version groups through per-file provenance and dependency review. Do not bulk-rename or delete them merely to satisfy filename validation.

## What this plan does not authorize

- No production DDL or migration push.
- No direct edits to `supabase_migrations.schema_migrations`.
- No marking migrations as applied to bypass replay.
- No reset, restore, or replacement of the production database.
- No fabricated SQL presented as the original September baseline.
- No promotion of inactive `.candidate` files into the active migration directory without provenance and replay evidence.

## Exit criteria

The baseline recovery is complete only when (a) historical sources are recovered or formally superseded by an approved new-environment bootstrap design, (b) the bootstrap replays from empty on a disposable database, (c) all required schema/security/application contracts pass, (d) the existing-environment upgrade path is independently verified, and (e) production migration history remains unchanged unless a separately approved official migration workflow requires a forward-only entry.

## Implementation checkpoint — 2026-11-27

The next implementation phase is explicitly split into two independent tracks. They must not share or rewrite migration-ledger identities.

### Track A — new disposable environment

1. Obtain an authoritative, complete schema-only export from the exact source environment approved for the new baseline. The previously inspected project reference `ygqoptvezotdqhtimdkr` is historical evidence only and is not automatically the current or authorized source.
2. Record export provenance (project reference, PostgreSQL version, export timestamp, operator, command/tool version, inclusion/exclusion policy, and SHA-256). Exclude patient/business data, Auth users, storage objects, secrets, and credentials.
3. Review application-owned versus Supabase-managed objects. Include object definitions and security metadata, not merely tables and columns.
4. Produce a separately named bootstrap artifact. It must not be placed under the historical migration timestamp `20260916002251`, must not be inserted into the hosted migration ledger, and must not be represented as the original `canonical_remote_schema`.
5. Replay only on a disposable empty PostgreSQL 17/Supabase-compatible environment. Capture the exact command, logs, schema fingerprint, generated types, and database-contract results.
6. Add a new-install CI job only after the artifact and its provenance are complete. The job must fail if the artifact's source metadata or checksum is absent.

### Track B — existing environment upgrades

1. Preserve the captured hosted ledger as historical evidence; it is not a substitute for original SQL or checksums.
2. Recover the missing original migration sources and independently verify the five late-October candidate sources.
3. Resolve each duplicate version group with both Git ancestry and SQL dependency/semantic evidence. Git ancestry alone is insufficient for divergent or shared-commit cases.
4. For each ordered collision group, retain a machine-readable resolution record with exact source blob hashes, chosen order, dependency evidence, and replay result. Leave unresolved groups blocked.
5. Compare the repository history against a fresh read-only ledger from the exact target environment before any upgrade plan is approved. Never infer the target from the historical project reference.
6. Create forward-only upgrade migrations only after the canonical target schema and authorization semantics are established. Do not apply them until the user confirms the exact environment and action.

### Current gate status

- The 21 duplicate timestamp groups remain a hard preflight failure; PostgreSQL startup and clean replay are skipped.
- The missing original `20260916002251_canonical_remote_schema.sql` remains an independent baseline-source gap.
- The five shared clinical-table definitions and their permissive RLS policy pairs remain unresolved; no canonical schema or facility/role/action matrix has been approved.
- The `20260912162000` service-order shape conflict remains unresolved; the source contract is evidence, not a repair.
- The latest PR Quality run passed, and static migration-parity contracts passed, but the migration identity/replay workflow failed at preflight. No clean database replay is claimed.
- No database was accessed or modified in this implementation checkpoint; no Supabase branch was created.

### Exit criteria for this phase

Do not call migration reconciliation complete until both tracks have their own reproducible artifacts and tests, every collision is resolved or explicitly excluded from the applicable bootstrap path with a documented reason, the empty-database replay passes, and an existing-environment upgrade is independently verified. A passing source-level contract alone is not an exit criterion.

## Authoritative project identified and read-only catalog checkpoint — 2026-11-27

The user identified `ygqoptvezotdqhtimdkr` as the project to inspect. The Supabase project metadata confirms `harmony-health-hub`, `ACTIVE_HEALTHY`, PostgreSQL 17.6.1.166 (engine 17), region `eu-central-1`.

A read-only inspection confirmed:
- 417 live migration ledger entries, from `20260916002251` through `20261026141054`, with zero duplicate ledger versions.
- Exact version/name identity equality between the live ledger and the repository's 417-entry `supabase/migration-ledger-baseline.json` (zero mismatches, zero missing, zero additional).
- 156 public tables in the verbose public table inventory.
- Current service_orders is status-based; the five shared HIMS tables contain hybrid/expanded columns from the two source candidates.
- Security/performance advisor findings are recorded in `docs/engineering/live-supabase-catalog-security-audit-2026-11-27.md`.

This inspection did **not** retrieve a complete schema-only export, object definitions for every function/trigger/policy/grant, extension configuration, or managed Supabase dependencies. It is not a bootstrap artifact and does not recover the original `20260916002251_canonical_remote_schema.sql` source. The 21 duplicate repository migration identities remain unresolved. No DDL/DML, migration apply, reset, Auth/storage change, or branch creation occurred.

The live project is now an identified read-only source for further catalog recovery. Any schema export/bootstrap creation must still use a supported complete dump process, exclude patient/business data and secrets, capture checksums/provenance, and be validated on a separate disposable PostgreSQL 17 environment. The live project itself remains untouched.

