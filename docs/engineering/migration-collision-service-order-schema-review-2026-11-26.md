# Service-order migration shape conflict and dashboard source guard — 2026-11-26

## Scope

Static review of repository SQL on the PR branch. No database was queried or changed. This report does not establish which duplicate migration was applied in any hosted environment.

## Canonical service-order shape

The original migration `20260911004959_e283cf8c-f6e8-4347-b4c0-689d591d33e4.sql` creates `public.service_orders` with a `status` column (initial default `pending_payment`).

The later lifecycle migration `20260911233000_phase2_service_order_payment_gating.sql` standardizes that same `status` column, including the `pending_payment_approval`, `released`, `in_progress`, `completed`, and `cancelled` states. It adds other lifecycle fields but does not replace the canonical state column.

The later hardening migration `20260916100000_harden_service_order_override_and_release_contract.sql` explicitly says it does not introduce `payment_status` or `fulfillment_status`; its RPCs use `service_orders.status`. The role dashboard migration `20260929200000_role_dashboard_kpi_cleanup.sql` also queries `service_orders.status`.

## Conflicting duplicate migration

The colliding file `20260912162000_hims_workflow_completion.sql` declares `CREATE TABLE IF NOT EXISTS public.service_orders` with a different shape: `payment_status` and `fulfillment_status`, but no `status`. It then creates an index on `(payment_status, fulfillment_status)` and installs a trigger function that reads/writes `NEW.fulfillment_status`.

This is not a harmless alternate declaration:

- **If the canonical table already exists**, `CREATE TABLE IF NOT EXISTS` does not add the alternate columns. The following index creation references missing columns and should stop the migration. If execution progressed through any path that installed the trigger, the trigger body also expects a field absent from the canonical row type.
- **If the alternate table is created first**, later lifecycle, override, and dashboard SQL expects `status`, while the alternate definition does not supply it. The migration sequence therefore has incompatible schema assumptions in either direction unless an authoritative reconciliation step exists.

The repository evidence establishes a source-level schema conflict, not the live deployed table shape or the actual historical execution order. Do not solve this by simply renaming the duplicate timestamp or adding both sets of status columns: that would create two competing state machines and could allow contradictory payment/release states.

## Dashboard active-role migration

The same review found that `20260929203000_active_dashboard_role_context.sql` derives a second function by applying literal text replacements to `pg_get_functiondef('public.get_role_dashboard_summary()')`. The required source function and exact replacement markers are present in the repository's preceding dashboard migration. The migration currently does not assert at SQL runtime that every replacement matched.

A source-level regression was added to the existing `scripts/role-dashboard-contract.mjs` test. It now pins:
- the canonical `service_orders.status` definition and lifecycle;
- the incompatible `payment_status` / `fulfillment_status` declaration and trigger dependency in the colliding migration;
- the downstream status-based dashboard and billing RPC expectations; and
- the exact dynamic active-role function replacement markers.

This regression detects source drift in CI. It does not make the historical SQL runtime-safe and does not substitute for a clean replay.

## Required resolution path

1. Recover and verify the original applied SQL and per-environment migration ledger for the duplicate group.
2. Establish the authoritative service-order table shape from a separately authorized, read-only catalog inspection or a disposable PostgreSQL replay.
3. Design one canonical state model and explicit data-preserving reconciliation for any existing rows and RPC callers.
4. Preserve old migration files; implement any correction as a separately reviewed forward migration only after the historical chain and target schema are proven.
5. Do not begin full clean replay while the 21 duplicate migration identities remain unresolved.

No historical migration SQL was edited, no migration was applied, and no Supabase branch was created.
