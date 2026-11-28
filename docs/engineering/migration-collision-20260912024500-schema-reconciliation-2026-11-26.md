# Duplicate 20260912024500 HIMS schema reconciliation review — 2026-11-26

## Result

The two migrations sharing version `20260912024500` are not equivalent alternatives. They encode different HIMS data models for five identically named tables, plus separate ward/bed and insurance table families. The Git DAG establishes that `global_hims_enterprise_operations.sql` precedes `global_hims_inpatient_emergency_theatre_insurance.sql` in repository history, but does not establish whether either file was deployed or which shape exists in a database.

## Five incompatible shared tables

| Table | Enterprise candidate | Global candidate | Consequence |
|---|---|---|---|
| `nursing_care_plans` | Nullable interventions; no patient FK; required creator with RESTRICT; admission link | Required interventions; patient FK CASCADE; nullable creator with SET NULL; encounter and reviewed_at | Existing rows and creator nullability cannot be reconciled by adding columns alone; FK and delete behavior differ |
| `nursing_shift_handovers` | admission_id, shift_date, shift_name, outstanding_tasks, risks_and_alerts | ward_id, shift_label, pending_tasks, safety_concerns; patient FK CASCADE | Different clinical handover workflow and ward linkage; the repository separately stages ward_id restoration |
| `emergency_cases` | arrival_at, triage_priority, optional chief_complaint, notes; status vocabulary includes transferred/deceased | arrival_time, acuity, required chief_complaint, triage_summary, disposition_at; different status vocabulary | Time, acuity and lifecycle values need semantic mapping; some enterprise statuses have no direct global equivalent |
| `theatre_cases` | theatre, anaesthetist_id, scheduled_at nullable, anaesthetic_cleared, consent_confirmed; planned/cleared lifecycle | theatre_name, anesthetist_id, scheduled_start required, scheduled_end, urgency, pre/post-op notes; requested/approved/scheduled lifecycle | Column spelling, scheduling constraints, clinical clearance fields and status values diverge |
| `transfusion_records` | component, optional unit_identifier, status includes verified/reaction, notes | blood_product, required unit_identifier, volume_ml, reaction_observed, status includes issued/cancelled | Product taxonomy, unit identity requirement, reaction representation and lifecycle differ |

The machine-readable manifest lists all candidate-only columns and the semantic differences that require explicit decisions.

## Additional distinct table families

The enterprise file creates `wards`, `beds`, and `insurance_cases`. The global file creates `ward_units`, `ward_beds`, `insurance_claims`, and `insurance_claim_events`. These are not duplicate table names, but they represent parallel models of the same operational domains. They must not be blindly merged or dropped: application consumers, foreign keys, RPCs and RLS policies need a canonical ownership decision.

## RLS and function side effects

Both files enable RLS on their own table sets and create role-based policies. On the five shared tables, policy names differ. PostgreSQL permissive policies are OR-combined for a role/command; applying both candidates can therefore broaden access beyond either candidate's intended policy set. A schema-only merge that ignores policies is unsafe.

The enterprise candidate defines `update_insurance_case`; the global candidate defines `touch_global_hims_updated_at` and `transition_insurance_claim`. Their functions and trigger arrangements are not interchangeable. The later security-hardening migrations must be reviewed against the chosen canonical model and exact function signatures.

## What is now implemented

- Added `docs/engineering/migration-collision-20260912024500-schema-manifest-2026-11-26.json`, an explicit inventory of the five shared-table shape differences, distinct table families, and non-replay disposition.
- Added `scripts/migration-20260912024500-schema-contract.mjs` and registered it under `test:migration-parity`. It checks exact candidate column sets, pins critical FK/nullability/workflow tokens, verifies distinct table families, and fails if the manifest is changed to authorize automatic merge, drop, dual-column expansion, or replay.
- Historical migration files remain untouched.

The contract is a source inventory guard. It does not validate live catalog state, data mappings, effective RLS policies, or a PostgreSQL replay.

## Reconciliation decision

No single canonical schema can responsibly be selected from repository chronology alone. Required evidence before creating a forward repair:

1. The exact authoritative database catalog for all shared and distinct tables, constraints, indexes, triggers, policies, function signatures, owners and ACLs.
2. Per-environment migration ledger and the exact SQL/blob deployed for each duplicate version.
3. Application/UI/RPC consumer inventory for both naming families and each status vocabulary.
4. A chosen canonical model with explicit mappings for statuses, nullable values, missing columns, patient/admission/encounter links, and ward/insurance relationships.
5. A disposable PostgreSQL 17 replay and regression suite for RLS, facility boundaries, clinical workflows and RPC behavior.

The user has confirmed that current database contents are test data and data loss is acceptable for the testing project. This permits considering a clean test-database reset as a future option, but it does not identify or authorize a specific database endpoint. No database was accessed or modified in this repository-only step. No Supabase branch was created.

## Migration gate

The 21 duplicate-version groups remain unresolved. The migration identity preflight must continue to fail before database services start. Do not renumber, delete, combine, or reorder historical migrations; do not synthesize migration-ledger rows; do not weaken the gate. A disposable clean database can validate a separately authored canonical fresh-install sequence only after the sequence and target are explicitly established.
