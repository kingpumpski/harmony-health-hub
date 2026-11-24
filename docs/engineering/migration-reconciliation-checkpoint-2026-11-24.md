# Migration and database engineering checkpoint

**Inspection date:** 2026-11-24  
**Repository:** `kingpumpski/harmony-health-hub`  
**Branch:** `chore/forward-only-migration-governance`  
**PR:** [#444](https://github.com/kingpumpski/harmony-health-hub/pull/444)  
**Inspected head:** `70b8887cb6750a239613968966bae3df507e7c71`  
**Hosted Supabase project:** `ygqoptvezotdqhtimdkr` (read-only inspection)

## Executive status

The work remains migration-first. The PR is open and draft. Quality CI passed, but the migration-contract workflow failed at the migration identity preflight. The clean replay job did not start Supabase services and did not execute a database reset or migration replay.

No production DDL, migration application, migration-ledger edits, or production resets were performed during this checkpoint.

## 1. CI evidence

For PR head `70b8887cb6750a239613968966bae3df507e7c71`:

- Quality run #8896: **passed**.
- Migration contract run #2815: **failed**.
- Forward-only regression and immutability/order checks passed.
- Schema/security contract stopped at `node scripts/migration-contract.mjs`.
- Clean replay stopped at the pre-start validation step. Supabase CLI setup, local database startup, clean replay, and post-replay schema/RPC/RLS checks were skipped.
- The validator reported the same 21 duplicate migration-version groups listed in the main reconciliation report. The invalid `$(path)` artifact is no longer present in the active migration directory.

The latest PR head and the generated merge-test commit were verified. The CI replay was run against merge commit `e07873d31acfe33f4c53c2bc8fa61afcea82553a`, which merges the inspected PR head into `main`.

## 2. Hosted migration ledger

A read-only query confirmed the latest hosted entries are:

- `20261026134619_reconcile_hr_payroll_record_management`
- `20261026134818_reconcile_inpatient_reviews_seen_at`
- `20261026135424_reconcile_laboratory_rpc_argument_contracts`
- `20261026135602_reconcile_laboratory_rpc_legacy_schema_compatibility`
- `20261026141054_reconcile_lab_catalogue_sample_quantity_rpc`

The latest hosted version remains `20261026141054`. No source-recovery commit search result was found for `canonical_remote_schema` or `20260916002251` in the connected repository search. This is not proof that an external workstation, deleted ref, archive, or CI artifact does not exist.

The repository still must not invent the missing historical baseline, impersonate its September version, or mark historical migrations applied to force alignment.

## 3. Additional live catalog inspection

Read-only PostgreSQL catalog checks returned:

| Area | Observation |
|---|---:|
| Public tables/partitioned tables | 156 |
| Public identity columns | 0 |
| Public columns with `nextval(...)` defaults | 0 |
| Public sequences | 0 |
| Public SECURITY DEFINER functions | 313 |
| SECURITY DEFINER functions without explicit function-level search_path configuration | 0 |
| Public tables with RLS enabled | 156 |
| Public tables with FORCE ROW LEVEL SECURITY | 0 |

The zero sequence counts apply to the public schema only. They are not evidence that no identity/sequence-backed objects exist in other schemas or in Supabase-managed infrastructure. The absence of FORCE RLS is recorded as an inventory fact, not automatically as a defect.

The project has five installed extensions: `pg_stat_statements` 1.11, `pgcrypto` 1.3, `plpgsql` 1.0, `supabase_vault` 0.3.1, and `uuid-ossp` 1.1.

## 4. Security advisor findings

The live security advisor currently reports:

- Two tables with RLS enabled but no policies: `public.lab_test_groups` and `public.lab_test_group_items`.
- One mutable function search path: `public.ensure_updated_at()`.
- 279 SECURITY DEFINER functions executable by the authenticated role. These are review candidates, not proof of 279 vulnerabilities; each RPC requires inspection of intended caller, authentication, authorization, tenant/facility scoping, ownership checks, and required client exposure before changing grants.

Catalog detail confirms both laboratory tables currently have broad ACL entries for `anon` and `authenticated`, including table-level privileges beyond ordinary CRUD. Their RLS is enabled but neither table has a policy. `public.ensure_updated_at()` is an invoker function owned by postgres and has no function-level `search_path` configuration.

The previously staged forward-only migration `20261123090000_harden_laboratory_panel_table_privileges_and_timestamp_trigger.sql` addresses the direct table grants and pins the trigger helper's search path. It remains **staged only**. It was not applied to production. Before application, validate all dependent trigger/function behavior and verify that no intended authenticated/anon direct access is required; the current lack of RLS policies suggests access is intended through controlled RPCs, but that must be confirmed against application call paths.

## 5. Performance advisor findings

The advisor reports 12 tables with multiple permissive policies for the same role/action and one duplicate-index pair on `public.lab_result_attachments`:

- `idx_lab_result_attachments_lab_result_id`
- `lab_result_attachments_result_idx`

It also reports unused indexes. No indexes were dropped: advisor usage counters alone do not establish that an index is safe to remove, especially after restarts or on infrequently used clinical/financial workflows. The multiple-policy findings need semantic equivalence and policy-plan review before consolidation.

## 6. Current blocker and next safe sequence

1. Recover original applied SQL and migration provenance from the pre-Supabase development environment, developer clones, archived exports, release bundles, deployment artifacts, and CI artifacts.
2. Build a per-collision manifest for all 21 version groups: file hashes, content relationships, branch/commit provenance, dependency ordering, and environment-ledger evidence. No bulk renumber/delete operation is authorized by the current evidence.
3. Recover the three missing late-October laboratory migration sources exactly, or explicitly record them as unrecovered. Runtime function-body equivalence is not full migration-source provenance.
4. Obtain a complete schema-only export from the authoritative hosted database, including grants/default privileges, functions, types, triggers, constraints, indexes, sequences/identity, extension versions/configuration, and relevant Supabase-managed configuration. A catalog count or generated TypeScript type file is not a substitute.
5. If historical recovery is impossible, design a distinct fresh-environment bootstrap with explicit provenance and a version later than `20261026141054`; validate it on a disposable empty PostgreSQL 17/Supabase environment. Keep the existing production upgrade path separate.
6. Keep the migration identity validator fail-closed. Only after all active migrations are unambiguous should CI proceed to clean replay and post-replay schema/security tests.
7. Review and verify the staged laboratory privilege/search-path migration and the SECURITY DEFINER advisor findings without making broad, speculative grant changes.

## Safety boundary

No production schema or data changes were made during this checkpoint. PR #444 remains draft and must not be merged as a completed migration reconciliation until source provenance, clean replay, and post-replay verification pass.
