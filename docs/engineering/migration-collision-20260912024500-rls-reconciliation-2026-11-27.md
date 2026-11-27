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
