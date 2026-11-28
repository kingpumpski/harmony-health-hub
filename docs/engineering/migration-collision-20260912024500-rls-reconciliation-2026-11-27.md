# HIMS collision RLS policy reconciliation — 2026-11-27

## Scope

This review compares the two migrations sharing version `20260912024500`:

- `20260912024500_global_hims_enterprise_operations.sql`
- `20260912024500_global_hims_inpatient_emergency_theatre_insurance.sql`

Both migrations enable RLS on the same five clinical tables and create differently named permissive `FOR ALL TO authenticated` policies.

## Findings

| Shared table | Enterprise policy | Global policy | Material difference |
|---|---|---|---|
| `nursing_care_plans` | `nursing care plans clinical` | `nursing care plan access` | Enterprise write check is role-only; global write check requires creator or admin |
| `nursing_shift_handovers` | `handover clinical` | `nursing handover access` | Global write check requires outgoing/incoming officer or admin |
| `emergency_cases` | `emergency clinical` | `emergency clinical access` | Global write check requires assigned officer, admin, or front desk |
| `theatre_cases` | `theatre clinical` | `theatre clinical access` | Global write check requires creator, surgeon, or admin |
| `transfusion_records` | `transfusion clinical` | `transfusion clinical access` | Global write check requires administrator/witness identity or admin |

Both sets are role-based and neither includes an explicit facility predicate in these policy definitions. The enterprise policies are generally broader on writes. The global policy write checks add actor/assignment constraints, but they do not compensate for the absence of facility scope.

PostgreSQL permissive policies are OR-combined for a role and command. Consequently, if both migrations execute against the same shared table, a row allowed by either policy remains allowed. The more restrictive global `WITH CHECK` does not narrow the enterprise policy's role-only write allowance; the combined result can be as permissive as the broader enterprise policy. The same OR-combination concern applies to the five shared clinical tables.

## Guard added

Added `scripts/migration-20260912024500-rls-contract.mjs` to `npm run test:migration-parity`. It pins all five policy pairs, checks that each is an authenticated permissive all-command policy with USING and WITH CHECK clauses, verifies that neither source policy contains a facility predicate, and pins selected actor-identity write checks in the global policies.

The contract is a source regression guard. It does not simulate PostgreSQL policy evaluation or prove deployed policy state.

## Release disposition

This is a confirmed security blocker, not a migration-order-only issue. Do not resolve it by renaming policy identifiers, assuming the stricter policy wins, or dropping either policy set without an approved canonical schema and consumer model.

A safe forward repair requires:
1. The authoritative deployed table definitions and current policy catalog for all five tables.
2. The canonical HIMS table family and application/RPC consumer inventory.
3. Explicit facility-scope and role/action decisions for each operation.
4. A forward migration that replaces the conflicting policy set with one reviewed policy model, including grants and RPC behavior.
5. Disposable PostgreSQL replay and role/facility matrix tests.

The table-definition conflict documented in the companion schema reconciliation remains unresolved. No migration is authorized for application until those dependencies are reconciled.

## Verification boundary

No database was accessed or modified, no SQL was applied, and no Supabase branch was created. The historical migration files remain unchanged. The duplicate timestamp identity gate still blocks PostgreSQL startup and clean replay.

## Live project catalog verification — 2026-11-27

A read-only inspection of project `ygqoptvezotdqhtimdkr` confirms all five tables exist with RLS enabled. The live catalog has a role-based **PERMISSIVE FOR ALL** policy on each table, plus two **RESTRICTIVE SELECT-only** policies: `facility isolation select` and `facility_identity_select_guard`. Because the facility policies are restrictive, they AND with permissive policies for SELECT; the earlier source-only warning must not be interpreted as proof that current SELECT isolation is absent.

The live write boundary is more specific:
- `nursing_shift_handovers`: authenticated INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER and MAINTAIN table privileges are present. Its permissive ALL policy uses role checks, while the restrictive facility policies apply only to SELECT.
- `nursing_care_plans`: authenticated UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER and MAINTAIN privileges are present (INSERT is not). Its permissive ALL policy uses role checks; restrictive facility policies apply only to SELECT.
- `emergency_cases`, `theatre_cases`, and `transfusion_records`: authenticated direct INSERT/UPDATE/DELETE privileges were not present at inspection. Their RPC paths still need exact-signature authorization review.

The actual live column sets are hybrid/expanded across both candidates (see `docs/engineering/live-supabase-catalog-security-audit-2026-11-27.md`). This is valuable mapping evidence, not approval to preserve duplicate columns forever.

## Completed live RPC and caller inventory — 2026-11-27

The application write-path inventory is now complete for the five shared tables:

- `nursing_shift_handovers`: the handover page uses `create_nursing_shift_handover` and `acknowledge_nursing_handover`; the dashboard/Edge Function only reads or subscribes. No direct table mutation caller was found.
- `nursing_care_plans`: Clinical Operations creates plans through `create_nursing_care_plan`; no direct mutation caller or current UI review caller was found.
- `emergency_cases`, `theatre_cases`, and `transfusion_records`: authenticated direct DML privileges are absent; lifecycle writes are through the clinical RPCs.

A fresh live catalog query found these nine RPCs SECURITY DEFINER, with `search_path = ''`, authenticated EXECUTE, and no anon EXECUTE:
`create_nursing_shift_handover`, `acknowledge_nursing_handover`, `create_nursing_care_plan`, `create_emergency_case`, `transition_emergency_case`, `create_theatre_case`, `transition_theatre_case`, `create_transfusion_record`, and `record_transfusion_event`. All inspected definitions include a facility-context check. Handover acknowledgement, emergency/theatre transitions, transfusion creation and transfusion event recording use row locks. The live catalog did not contain `review_nursing_care_plan`.

The targeted forward repair is staged in `supabase/migrations/20261127103000_lock_nursing_lifecycle_table_writes.sql`: revoke PUBLIC/anon table access and authenticated direct INSERT/UPDATE/DELETE on the two nursing tables, preserving authenticated SELECT under RLS and the existing RPC write paths. Static source and database ACL contracts were added. It is not applied.

The role-based permissive ALL policies remain a policy-design concern and should be reconciled with an approved role × facility × action matrix. The staged grant correction removes the currently unnecessary direct table-write path, but does not claim to replace or fully reconcile the historical policy definitions.

No policy or grant was changed in the hosted database. The staged migration remains unapplied pending duplicate-history reconciliation, disposable PostgreSQL replay, and positive/negative facility tests.
