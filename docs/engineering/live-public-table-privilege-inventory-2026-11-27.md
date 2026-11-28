# Live public-table privilege inventory — 2026-11-27

## Scope and safety

Read-only catalog inspection of Supabase project `ygqoptvezotdqhtimdkr` (PostgreSQL 17). No DDL, DML, migration, reset, Auth/Storage setting, or branch operation was performed.

This is an ACL inventory, not a penetration test and not proof that a role can read or modify rows. PostgreSQL table privileges and row-level security are separate gates. A role needs the relevant table privilege and an applicable RLS policy (unless the role bypasses RLS).

## Aggregate findings

The public schema contains 156 ordinary/partitioned tables.

| Check | Count |
|---|---:|
| Tables with RLS enabled | 156 / 156 |
| Tables with RLS disabled | 0 |
| Tables where `anon` has effective SELECT | 110 |
| Tables where `anon` has effective INSERT, UPDATE, or DELETE | 93 |
| Tables where `anon` has effective TRUNCATE, REFERENCES, TRIGGER, or MAINTAIN | 111 |
| Tables where `authenticated` has effective INSERT, UPDATE, or DELETE | 78 |
| Tables where `authenticated` has effective TRUNCATE, REFERENCES, TRIGGER, or MAINTAIN | 132 |

Counts use PostgreSQL `has_table_privilege`, which includes privileges inherited through grants. They must not be interpreted as counts of exploitable tables.

## Representative ACL evidence

Catalog ACL strings show explicit grants to both API roles on multiple tables. Examples:

- `ai_case_memory`: `anon=arwdDxtm`, `authenticated=arwdDxtm`.
- `lab_test_groups`: `anon=arwdDxtm`, `authenticated=arwdDxtm`.
- `nursing_shift_handovers`: `anon=arwdDxtm`, `authenticated=arwdDxtm`.
- `patient_audit`: `anon=arwdDxtm`, `authenticated=arwdDxtm`.
- `scheduled_notifications`: `anon=arwdDxtm`, `authenticated=arwdDxtm`.
- By contrast, `patients` had read-only ACLs for both API roles (`rDxtm`), and `admissions` did not grant INSERT/UPDATE/DELETE to either API role.

The privilege letters include PostgreSQL 17 `MAINTAIN` (`m`) as well as TRUNCATE (`D`), REFERENCES (`x`) and TRIGGER (`t`). These non-DML grants should be included in any least-privilege review.

## Interpretation and next actions

1. Treat broad API-role ACLs as privilege hygiene and exposure-surface findings. RLS is enabled on all 156 tables, but policy coverage and role targeting must be checked per table and command before inferring row access.
2. Prioritize sensitive tables with explicit `anon` grants, including audit, patient, nursing, billing, HR, and notification-related tables. Confirm whether each table is intentionally exposed to the anon API role and whether any applicable policy exists for anon/PUBLIC.
3. Inventory application callers, RPCs, Edge Functions, service-role workflows, and generated client types before revoking any grant. Do not blanket-revoke authenticated writes where the application still depends on direct writes.
4. Prepare narrowly scoped, forward-only privilege migrations only after each table's intended access contract is approved. Preserve service-role/owner paths and test both positive and negative role cases.
5. Add catalog-level regression assertions to the database contract suite. Run those assertions only after the historical migration source/replay blocker has been resolved and a disposable PostgreSQL replay is available.

## Important limitation

The live migration ledger provides version/name identities, not original SQL checksums. This ACL snapshot does not identify which historical migration introduced each grant and does not authorize rewriting historical migration files. It also does not establish that a clean replay produces the current hosted ACL state.

## Verification checkpoint

On PR head `f11d0b111afe8dedbe1f1b6f07960636e6412b5a`:

- Quality run [#9524](https://github.com/kingpumpski/harmony-health-hub/actions/runs/46026179713) passed.
- Migration contract run [#3192](https://github.com/kingpumpski/harmony-health-hub/actions/runs/46026180373) failed at duplicate migration-version preflight. PostgreSQL setup, clean replay, and runtime SQL contracts were skipped.

No hosted database changes were made.
