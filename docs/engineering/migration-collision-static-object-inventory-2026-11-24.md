# Migration collision static object inventory — 2026-11-24

## Scope and method

This report adds a repository/archive-level inventory for all 21 duplicate 14-digit migration versions in the supplied `harmony-health-hub.zip` (651 SQL migration files, 628 distinct version prefixes). It extracts explicit `CREATE TABLE`, `ALTER TABLE`, `CREATE OR REPLACE FUNCTION`, `CREATE TYPE`, and `CREATE INDEX` declarations from source text and compares names within each duplicate-version group.

This is a deliberately conservative text scan, not a PostgreSQL parser. It can miss quoted identifiers, dynamic SQL, policies, grants, triggers, views, overloaded signatures, references in function bodies, and syntax variants. Absence from this inventory is not proof of no interaction. The archive has no Git history, so these findings do not establish provenance or deployment state.

## Result

Only one duplicate-version group had matching table names in both candidates under this declaration scan:

| Version | Shared table declarations | Consequence |
|---|---|---|
| `20260912024500` | `emergency_cases`, `nursing_care_plans`, `nursing_shift_handovers`, `theatre_cases`, `transfusion_records` | Both candidates declare and alter the same five tables. `IF NOT EXISTS` does not reconcile an already-created table's columns, constraints, or defaults. This group requires full DDL reconciliation. |

No other group had same-named explicit table declarations in both files under this scan. That does not mean those pairs are independent: function replacement, grants, policies, triggers, dynamic SQL, and dependencies can still overlap.

## Collision groups and static declaration summary

- `20260912003000`: imaging order/payment-gate objects vs triage assessment objects.
- `20260912010000`: anesthetic assessment objects vs AI clinical session/event objects.
- `20260912021000`: attending patient-history RPC vs global HIMS configuration, maternity, and audit objects.
- `20260912024500`: overlapping inpatient/emergency/theatre/insurance table definitions (five shared table names above), plus distinct ward/beds/claims objects and lifecycle functions.
- `20260912162000`: clinical audit trigger/function hardening vs a workflow migration creating facility settings, inpatient reviews, laboratory catalogue/parameters, patient audit, and service orders.
- `20260912200000`: laboratory catalogue/audit objects vs prescription payment/dispensing status synchronization functions.
- `20260912250000`: laboratory direct-write lockdown vs broader reconciliation-finalization privilege changes. Both touch lab write permissions; compare the complete relation/role/privilege matrix.
- `20260913180000`: appointment workflow functions vs report-submission RBAC function.
- `20260914140000`: pharmacy direct-mutation RPC hardening vs theatre/emergency/transfusion lifecycle RPCs and table changes.
- `20260914150000`: admission/bed mutation boundary vs clinical claim/nursing mutation boundary.
- `20260914170000`: insurance-case mutation boundary vs triage/medication mutation boundary.
- `20260915170000`: security-definer EXECUTE hardening vs insurance-claim duplicate-index cleanup.
- `20260925200000`: notification audit immutability vs inbound-email storage/RLS objects.
- `20260929100000`: ward table API boundary vs insurance-company master data and related foreign-key columns/RPCs.
- `20260929103000`: operational workspace search-path hardening vs service-catalogue department-control RPC.
- `20260929150000`: canteen/dietary workspace schema vs operational workspace RPC hardening vs canonical patient-insurer linkage.
- `20260929200000`: canteen menu RLS/realtime changes vs dashboard KPI RPC vs default function EXECUTE privileges.
- `20260929203000`: active dashboard role context transformation vs workspace SECURITY DEFINER search-path hardening.
- `20260930012000`: department queue multi-role authorization vs high-risk RPC EXECUTE/search-path boundaries.
- `20261002130000`: global pharmacy catalogue/facility stock/safety vs active-facility appointment workflow scoping.
- `20261002132500`: patient-hub read RPC compatibility vs pharmacy global category editing.

## Ordering hazards confirmed by source inspection

1. `20260929203000_active_dashboard_role_context.sql` reads `pg_get_functiondef('public.get_role_dashboard_summary()'::regprocedure)`, transforms the retrieved body, and creates/replaces role-specific dashboard functions. It therefore depends on a compatible prior definition of `get_role_dashboard_summary()`. The same-version `20260929200000_role_dashboard_kpi_cleanup.sql` is a candidate prerequisite, but only original provenance and replay can establish the intended ordering.
2. `20260929200000_secure_default_function_execute_privileges.sql` changes default privileges for future functions created by selected owner roles. Its relative position to later function-creation migrations changes which newly created functions inherit those defaults.
3. `20261002130000_scope_appointment_workflows_to_active_facility.sql` replaces appointment workflow function signatures/implementations, while the same-version pharmacy candidate introduces pharmacy catalogue and facility-stock behavior. They are different feature tracks, not competing implementations of one migration.
4. The two `20260912024500` candidates both declare/alter the five shared tables listed above. A replay can silently preserve whichever definition arrived first when `CREATE TABLE IF NOT EXISTS` is used; later ALTER statements may only partially reconcile it.

## Required next verification

- Parse every candidate with a PostgreSQL-aware parser and build full object/signature/dependency inventories.
- Compare the five shared table definitions from `20260912024500` against the authoritative catalog: columns, types, nullability, defaults, generated/identity attributes, primary/foreign/unique/check constraints, indexes, RLS, policies, triggers, and grants.
- For every function collision/evolution, compare argument types, return type, volatility, security mode, owner, search_path, ACL, body, and dependencies.
- Reconstruct owner-role default-privilege state at each migration boundary.
- Replay candidate histories on disposable PostgreSQL 17 instances and verify the resulting catalog against the canonical schema snapshot.
- Keep historical hosted migration versions and the new-environment bootstrap as separate tracks. Any fresh bootstrap must use a new version later than the canonical hosted maximum `20261026141054`; it must not impersonate a missing September baseline.

## Disposition

No migration was renamed, deleted, combined, promoted, or applied. No hosted Supabase project was changed. The report is static evidence to guide the next provenance and replay phase, not approval to execute SQL.
