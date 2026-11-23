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
