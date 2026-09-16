# Production Migration Baseline Reconciliation

## Purpose

This document records the current migration-history boundary between the `main` repository and the linked production Supabase project. It is intentionally descriptive: it does not attempt to recreate or guess the SQL behind a remote baseline migration.

## Current state

Production project: `ygqoptvezotdqhtimdkr`.

The production `supabase_migrations.schema_migrations` ledger currently contains only:

- `20260916002251` — `canonical_remote_schema`
- `20260916003113` — `fix_start_imaging_order_queue_contract`
- `20260916085626` — `reconcile_imaging_lifecycle_server_authority`

The first two migration versions/names are not present in the repository's `supabase/migrations` directory on `main`.

The repository does contain the source migration
`20260914130000_imaging_lifecycle_server_authority.sql`, whose SQL is the source for the imaging lifecycle reconciliation represented by the later production migration `20260916085626`.

## Why this is a controlled migration boundary

The production schema has already been reconciled independently of the repository's historical migration ledger. The repository still contains a large historical migration chain, while production is tracking a canonical remote schema baseline instead of those historical versions.

Because the SQL for `canonical_remote_schema` and `fix_start_imaging_order_queue_contract` has not been recovered, the repository must not fabricate replacement migrations for them.

## Required rules

Until the baseline is explicitly reconciled:

1. Do **not** run `supabase db push --include-all` against production.
2. Do **not** edit `supabase_migrations.schema_migrations` directly.
3. Do **not** mark historical migrations as applied merely to make the ledger resemble the repository.
4. Do **not** create duplicate migration files solely to mirror the remote version numbers.
5. Use the approved Supabase migration workflow for genuine schema changes.
6. Treat production schema inspection as read-only unless an approved migration is being applied.
7. After any approved migration, verify the resulting production schema and permissions with read-only checks.

## Reconciliation target

The desired end state is:

- production schema remains intact;
- the repository contains the authoritative future migration chain;
- migration tracking is reconciled using the official Supabase migration tooling rather than direct ledger edits;
- future `validate`/`apply`/`verify` workflow runs can determine pending migrations without attempting to replay the historical schema;
- application contracts remain tested against the actual production schema.

## Evidence currently established

The production schema has already been verified for the operational read contracts used by Theatre, Insurance Claims, Pharmacy, and Accounts. The imaging lifecycle RPCs have also been reconciled to server-authoritative execution and verified after application.

The remaining migration-baseline task is therefore a **migration tracking reconciliation**, not a request to rebuild or overwrite the production schema.
