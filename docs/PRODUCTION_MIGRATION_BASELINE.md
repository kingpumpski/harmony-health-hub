# Production Migration Baseline Reconciliation

## Purpose

This document records the current migration-history boundary between the `main` repository and the linked production Supabase project. It is intentionally descriptive: it does not attempt to recreate or guess the SQL behind a remote baseline migration.

## Current state

Production project: `ygqoptvezotdqhtimdkr`.

The production `supabase_migrations.schema_migrations` ledger currently contains the canonical baseline and subsequent production reconciliations:

- `20260916002251` — `canonical_remote_schema`
- `20260916003113` — `fix_start_imaging_order_queue_contract`
- `20260916085626` — `reconcile_imaging_lifecycle_server_authority`
- `20260916092730` — `reconcile_service_order_workflow_authority`
- `20260916093000` — `harden_service_order_rpc_execute_boundary`
- `20260916093154` — `reconcile_service_order_lifecycle_metadata`
- `20260916093512` — `harden_selected_invoice_payment_service_release`
- `20260916093546` — `complete_selected_invoice_service_order_release`
- `20260916093817` — `allow_front_desk_payment_release_boundary`
- `20260916094245` — `harden_service_order_override_and_release_contract`
- `20260916103212` — `add_missing_foreign_key_indexes`
- `20260916103904` — `optimize_rls_auth_uid_initplans`
- `20260916103929` — `normalize_rls_auth_uid_initplans`
- `20260916105508` — `harden_internal_trigger_function_execute_boundary`
- `20260916105824` — `harden_pharmacy_rpc_authorization_boundary`
- `20260916110729` — `harden_authorization_helper_execute_boundary`

The first two migration versions/names are not present in the repository's `supabase/migrations` directory on `main`. The later production reconciliation versions are also recorded under repository source migrations with different local filenames in some cases. This is expected to be treated as provenance rather than an instruction to fabricate duplicate migration files or rewrite the production ledger.

## Production-only migration provenance

The following production ledger entries were confirmed by the current live migration list but do not have matching filenames by those exact version numbers in the repository:

- `20260916002251` — canonical remote schema baseline
- `20260916003113` — imaging queue contract repair
- `20260916085626` — imaging lifecycle server-authority reconciliation
- `20260916092730` — service-order workflow authority reconciliation
- `20260916093000` — service-order RPC execute-boundary hardening
- `20260916093154` — service-order lifecycle metadata reconciliation
- `20260916093512` — selected-invoice payment/service release hardening
- `20260916093546` — selected-invoice service-order release completion
- `20260916093817` — front-desk payment release boundary
- `20260916094245` — service-order override/release contract hardening
- `20260916103212` — foreign-key index reconciliation
- `20260916103904` — RLS `auth.uid()` initplan optimization
- `20260916103929` — RLS auth-expression normalization
- `20260916105508` — internal trigger-function execute-boundary hardening
- `20260916105824` — pharmacy RPC authorization-boundary hardening
- `20260916110729` — authorization-helper execute-boundary hardening

These entries are evidence of the actual production migration history. They are not to be recreated as duplicate repository migrations solely to make version numbers match.

## Repository-to-production source mapping

The repository contains source migrations whose SQL represents several of the production reconciliations under later production-generated migration versions. In particular:

- `supabase/migrations/20260914130000_imaging_lifecycle_server_authority.sql` is the repository source for the imaging lifecycle reconciliation represented in production by `20260916085626`.
- The service-order compatibility and payment-gating migrations remain the repository references for the production service-order contract.
- The FK-index, RLS, trigger-boundary, pharmacy-boundary and authorization-helper hardening migrations are represented in `main` by their repository source files and should not be duplicated merely to mirror production-generated timestamps.

The exact SQL behind `canonical_remote_schema` and `fix_start_imaging_order_queue_contract` has not been recovered. No replacement baseline migration has been fabricated.

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

A subsequent read-only contract audit identified that the restored RPC/event contract referenced four lifecycle metadata columns that were absent from the canonical production schema: `released_at`, `released_by`, `release_reason`, and `cancelled_at`. These were restored additively through the approved lifecycle-metadata reconciliation, with existing approval timestamps/users backfilled into release metadata where appropriate. No existing service-order rows were otherwise rewritten.

The resulting RPCs remain `SECURITY DEFINER`, use the existing role/clinical-staff authorization helpers, deny anonymous execution, and are executable by authenticated clients through the intended workflow boundary. The resulting schema and RPC presence were verified with read-only production checks after application.

## Billing release boundary

The production `pay_selected_invoice_items()` workflow creates or locates the service order associated with each paid invoice item and delegates release to the authoritative `release_service_order()` RPC. A production verification identified an authorization mismatch: billing collection permitted `front_desk`, while `release_service_order()` previously permitted only `admin` and `accountant`. This meant a legitimate front-desk payment could be recorded but fail during the required release step.

The approved front-desk reconciliation aligned the release authorization with the existing billing collection workflow. `release_service_order()` remains `SECURITY DEFINER`, denies anonymous execution, remains authenticated-only, and now permits the `front_desk` role in addition to `admin` and `accountant`. The payment gate, override handling, queue synchronization, and lifecycle metadata remain unchanged.

A follow-up hardening reconciliation preserved the same release boundary while adding a state guard to `grant_service_order_override()`: an override can only be granted while the service order is still `pending_payment_approval`. Both billing RPCs remain anonymous-denied and authenticated-only. The repository security contract explicitly checks both the front-desk release boundary and the override state boundary.

## Application service-order creation parity

The frontend service-order creation helper persists the optional `invoice_item_id`, `order_type`, and `service_code` fields instead of silently dropping values supplied by callers. When no order type is supplied, it explicitly persists the existing database default semantic of `service`. This preserves the current schema while preventing metadata loss for procedure and other billable workflow callers.

## Why this is a controlled migration boundary

The production schema has already been reconciled independently of the repository's historical migration ledger. The repository contains a large historical migration chain, while production is tracking a canonical remote schema baseline instead of those historical versions.

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

The production schema has been verified for the operational read contracts used by Theatre, Insurance Claims, Pharmacy, and Accounts. The imaging lifecycle RPCs have been reconciled to server-authoritative execution and verified after application. The service-order compatibility contract and lifecycle metadata dependencies have also been reconciled and verified. The selected-invoice payment release path has been verified as authenticated-only and now has an authorization contract covering the existing front-desk billing workflow. The service-order override boundary has also been verified as authenticated-only and state-restricted to pending payment approval. FK coverage, RLS auth-expression optimization, internal trigger execution boundaries, pharmacy authorization boundaries, and arbitrary-user authorization-helper execution boundaries have subsequently been reconciled and recorded in production.

The remaining migration-baseline task is therefore a **migration tracking reconciliation**, not a request to rebuild or overwrite the production schema.
