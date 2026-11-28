# Live Supabase catalog and security checkpoint — 2026-11-27

## Target and method

- Confirmed project reference: `ygqoptvezotdqhtimdkr` (`harmony-health-hub`).
- Project status at inspection: `ACTIVE_HEALTHY`.
- PostgreSQL: 17.6.1.166 (engine 17), region `eu-central-1`.
- Inspection date: 2026-11-27 (UTC; advisor observations around 14:30 UTC).
- Operations performed: project metadata, migration ledger, public table/column/FK inventory, extension inventory, generated TypeScript schema retrieval, Supabase security/performance/health advisors, and read-only catalog SELECTs.
- No application data was selected. No DDL, DML, Auth changes, storage changes, migration application, reset, branch creation, or project setting changes were performed.

This is a **catalog and advisor snapshot**, not a complete schema-only export. It does not recover the original SQL for the historical canonical baseline and cannot yet serve as a clean-install bootstrap artifact.

## Migration ledger reconciliation

The live project reports 417 migration entries, all with unique version identities:

- First: `20260916002251 canonical_remote_schema`.
- Last: `20261026141054 reconcile_lab_catalogue_sample_quantity_rpc`.
- Duplicate versions in the live ledger: 0.

The repository's `supabase/migration-ledger-baseline.json` contains 417 entries. A full version/name comparison against the live ledger found **zero missing entries, zero additional entries, and zero name mismatches**. The repository snapshot captured on 2026-11-23 is therefore still identity-equivalent to this project's ledger at this inspection.

This does not resolve the 21 duplicate filenames in the repository migration directory. Those collisions are a source-history/replay problem, not duplicate rows in the live ledger. The live ledger records identities, not original SQL bodies or checksums. The missing `20260916002251_canonical_remote_schema.sql` source remains unrecovered.

## Live schema findings relevant to existing collision reports

### Service orders

The live `public.service_orders` table contains the canonical `status` field (default `pending_payment_approval`) and lifecycle fields such as `approved_at`, `released_at`, `started_at`, `completed_at`, and `cancelled_at`. It does not contain the divergent `payment_status` or `fulfillment_status` columns.

This confirms the current deployed table is status-based. It does not prove which colliding historical file was executed or provide its original SQL. The conflicting migration remains unsafe for clean replay.

### Five shared HIMS clinical tables

All five live tables exist and have RLS enabled. Their live columns show a hybrid/expanded shape that includes fields from both source candidates:

- `nursing_care_plans`: `interventions`, `admission_id`, `encounter_id`, `reviewed_by`, `facility_id`.
- `nursing_shift_handovers`: `admission_id`, `shift_date`, `shift_name`, `outstanding_tasks`, `risks_and_alerts`, `pending_tasks`, `safety_concerns`, `shift_label`, `facility_id`.
- `emergency_cases`: both `arrival_at` and `arrival_time`, both `triage_priority` and `acuity`, plus `facility_id`.
- `theatre_cases`: both `theatre` and `theatre_name`, both `anaesthetist_id` and `anesthetist_id`, both `scheduled_at` and `scheduled_start`, plus `facility_id`.
- `transfusion_records`: both `component` and `blood_product`, both `reaction_notes` and `reaction_observed`, plus `facility_id`.

These live shapes are evidence for a compatibility mapping exercise. They are not a recommendation to keep every duplicate column indefinitely; each pair needs consumer inventory, nullability/default analysis, value mapping and a tested deprecation plan.

### Actual RLS policy behavior and table grants

The live catalog has one role-based **PERMISSIVE FOR ALL** policy on each of the five shared tables, plus two **RESTRICTIVE SELECT-only** facility guards:

- `facility isolation select`
- `facility_identity_select_guard`

The SELECT guards are restrictive, so they are ANDed with the permissive SELECT policy; they do not simply lose to it. The important remaining gap is that these restrictive guards apply only to SELECT. They do not constrain INSERT/UPDATE checks.

The live privilege check found:

| Table | Authenticated SELECT | INSERT | UPDATE | DELETE |
|---|---:|---:|---:|---:|
| nursing_care_plans | yes | no | yes | yes |
| nursing_shift_handovers | yes | yes | yes | yes |
| emergency_cases | yes | no | no | no |
| theatre_cases | yes | no | no | no |
| transfusion_records | yes | no | no | no |

Consequently, the highest-priority direct-write review is:
1. `nursing_shift_handovers`: authenticated direct INSERT/UPDATE/DELETE are granted, and its permissive ALL policy is role-based without facility scope in its write predicates.
2. `nursing_care_plans`: authenticated direct UPDATE/DELETE are granted; its permissive ALL policy has role-based write predicates without facility scope. Review UPDATE row visibility and especially `WITH CHECK` to prevent facility reassignment.

The other three tables do not currently grant authenticated direct writes, so their write-policy risk is not equivalent. Their RPC paths and execute grants still require signature-specific review. Do not blanket-revoke grants or alter policies without checking application callers and RPC behavior.

For the inspected tables, `anon` has table privileges inherited through existing grants, but no matching anon policies were found in the policy inventory; RLS remains enabled. Review broad inherited grants as part of the least-privilege audit, but do not infer anonymous row access from table privileges alone.

### Patient audit privacy

The live `patient_audit` table has RLS enabled and stores `old_record` and `new_record` JSONB columns. Its observed SELECT policy is `admins read patient audit`, based on the admin role and without a facility predicate. Authenticated table privileges include SELECT/INSERT/UPDATE/DELETE, but the inspected policy inventory contains only SELECT; RLS therefore remains a separate gate for mutations.

The trigger function `audit_patient_changes()` is SECURITY DEFINER and has `search_path=pg_catalog, public`. The full-row JSONB payload and broad admin read scope need a privacy review: explicit field minimization, facility-aware audit visibility, retention, and a fixed safe search path should be considered in a forward repair. Preserve auditability while minimizing copied patient data.

## Supabase advisor snapshot

### Security

- 2 INFO: RLS enabled with no policies — `lab_test_groups`, `lab_test_group_items`. Their intended RPC-only access model and table grants need verification.
- 1 WARN: `public.ensure_updated_at` has mutable search_path.
- 279 WARN: SECURITY DEFINER functions executable by `authenticated`. This is a review inventory, not proof that all 279 are exploitable. Review exact signatures, callers, ownership, function body authorization, search_path and grants; do not blanket revoke.
- 1 WARN: leaked-password protection is disabled in Auth. This is a project-level Auth setting, not a SQL migration.

### Performance

- 4 INFO: unindexed foreign keys.
- 4 WARN: auth/RLS initplan findings.
- 446 INFO: unused indexes. Validate statistics reset time and representative workload before dropping any index.
- 12 WARN: multiple permissive policies.
- 1 WARN: duplicate indexes on `lab_result_attachments` (`idx_lab_result_attachments_lab_result_id` and `lab_result_attachments_result_idx`).

### Health

The Supabase health advisor returned no findings at the time of inspection.

## Next implementation order

1. Add a targeted forward-only policy/grant repair for direct writes to `nursing_shift_handovers` and `nursing_care_plans`, but only after reviewing their RPC and UI write paths and defining the facility/role/action matrix. Validate with role × facility SQL tests.
2. Define a patient-audit payload minimization and facility-scoped read model; review `audit_patient_changes()` and `ensure_updated_at()` with exact signatures and dependent triggers before changing either.
3. Inventory the 279 SECURITY DEFINER findings by signature, ACL, search_path, and body-level authorization. Prioritize public/exposed functions with broad or missing authorization.
4. Verify the two RPC-only lab tables' grants and intended call surface.
5. Reconcile the 4 unindexed FKs, 4 initplan findings, and duplicate index. Treat the 446 unused-index notices as advisory until workload evidence is available.
6. Continue the 21 migration collision resolution and missing canonical source recovery. The live catalog snapshot cannot replace the missing original SQL or a complete schema-only dump.
7. Generate and compare repository TypeScript types against the live generated types, then run clean replay on a disposable PostgreSQL 17 environment after the duplicate-identity and baseline gates are resolved.

## Verification boundary

This inspection was read-only. No database changes were made. No migration was applied, no data was reset, no Supabase branch was created, and no clean replay is claimed. PR #444 remains the repository workstream; keep it draft and unmerged until the replay and security gates pass.
