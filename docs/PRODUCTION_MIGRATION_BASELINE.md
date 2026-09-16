# Production Migration Baseline Reconciliation

## Purpose

This document records the current migration-history boundary between the `main` repository and the linked production Supabase project. It is intentionally descriptive: it does not attempt to recreate or guess the SQL behind a remote baseline migration.

## Current state

Production project: `ygqoptvezotdqhtimdkr`.

The production `supabase_migrations.schema_migrations` ledger currently contains the canonical baseline and subsequent production reconciliations, including:

- `20260916002251` — `canonical_remote_schema`
- `20260916003113` — `fix_start_imaging_order_queue_contract`
- `20260916085626` — `reconcile_imaging_lifecycle_server_authority`
- the later approved `reconcile_service_order_workflow_authority` application, whose generated ledger version should be treated as production evidence rather than fabricated into the repository migration filename.

The first two migration versions/names are not present in the repository's `supabase/migrations` directory on `main`.

The repository contains the source migration `20260914130000_imaging_lifecycle_server_authority.sql`, whose SQL is the source for the imaging lifecycle reconciliation represented by the later production migration `20260916085626`.

## Service-order reconciliation

Production service-order infrastructure was audited against the repository's compatibility-layer contract. The live schema was missing the Phase 2 compatibility columns and four service-order workflow RPCs, while `release_service_order` existed with a weaker implementation.

The approved production reconciliation restored the canonical service-order workflow contract without introducing the repository's separate `payment_status`/`fulfillment_status` state-machine columns. It restored:

- billing override approval metadata and service-order linkage;
- department-queue service-order linkage and claim timestamps;
- service-order foreign keys and uniqueness guards;
- `grant_service_order_override`;
- payment/override-aware `release_service_order`;
- `cancel_service_order`;
- `mark_service_order_in_progress`;
- `complete_service_order`.

The resulting RPCs remain `SECURITY DEFINER`, use the existing role/clinical-staff authorization helpers, and are executable by authenticated clients through the intended workflow boundary. The resulting schema and RPC presence were verified with read-only production checks after application.

The repository's existing source migration `20260911241000_phase2_legacy_queue_compatibility.sql` remains the reference implementation for this compatibility contract. It is not duplicated under a new migration filename because production migration history is already baselined independently.

## Why this is a controlled migration boundary

The production schema has already been reconciled independently of the repository's historical migration ledger. The repository still contains a large historical migration chain, while production is tracking a canonical remote schema baseline instead of those historical versions.

Because the SQL for `canonical_remote_schema` and `fix_start_imaging_order_queue_contract` has not been recovered, the repository must not fabricate replacement migrations for them.

## Required rules

Until the baseline is explicitly reconciled:

1. Do **not** run `supabase db push --include-all` against production.
2. Do **not** edit `supabase_migrations.schema_migrations` directly.
3. Do **not** mark historical migrations as applied merely to make the ledger resemble the repository.
4. Do **not** create duplicate migration files solely to mirror remote version numbers.
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

The production schema has been verified for the operational read contracts used by Theatre, Insurance Claims, Pharmacy, and Accounts. The imaging lifecycle RPCs have been reconciled to server-authoritative execution and verified after application. The service-order compatibility contract has now also been reconciled and verified.

The remaining migration-baseline task is therefore a **migration tracking reconciliation**, not a request to rebuild or overwrite the production schema.
