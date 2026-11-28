# Cross-module database schema completeness audit — 2026-11-25

## Scope and evidence

This audit compares the canonical Supabase project catalog (`ygqoptvezotdqhtimdkr`) with the application's generated Supabase TypeScript schema and the module schema contracts on `chore/forward-only-migration-governance`.

The canonical database was inspected read-only. No production/canonical DDL, data, grants, RLS policies, functions, or migration ledger entries were changed during this audit.

## Canonical catalog snapshot

| Catalog measure | Observed |
| --- | ---: |
| Public tables | 156 |
| Public tables with RLS enabled | 156 |
| Public tables without RLS | 0 |
| Public indexes | 681 |
| Foreign-key constraints | 389 |
| Check constraints | 192 |

RLS being enabled on every public table is a useful baseline, but it does not prove that each table has correct policies or that each policy enforces facility and role boundaries.

## Generated TypeScript schema drift corrected

The repository's previous `src/integrations/supabase/types.ts` was materially behind the canonical database. Examples included:

- Several active operational tables were missing from the generated type file entirely, including `nursing_shift_handovers`, `emergency_cases`, `imaging_orders`, `hr_employees`, `payroll_periods`, `payroll_items`, `theatre_cases`, `transfusion_records`, `ward_units`, `ward_beds`, `care_transitions`, and `patient_referrals`.
- The old `appointments` type did not describe live columns such as `appointment_date`, `provider_id`, `consultation_type`, and `facility_id`.
- The old `admissions` type omitted live fields including `facility_id`, `created_by`, `diagnosis`, and `admitting_practitioner`.

The generated types were refreshed from the canonical Supabase catalog and committed. The refreshed output contains 156 public table types. This aligns compile-time database typing with the inspected live schema; it does not itself repair the migration history or alter the database.

## Automated module contracts added

Added `scripts/module-schema-contract.mjs` and the `test:module-schema-contract` npm script, wired into the Quality workflow.

The contract checks 48 module table definitions and their required columns across these workflow domains:

- Patient registration and identity
- Appointments, encounters, triage and vital signs
- Admissions, bed movements, wards and bed management
- Nursing notes, care plans and shift handovers
- Emergency, theatre, anaesthesia and transfusion
- Laboratory orders, specimens, catalogue and results
- Diagnostic imaging
- Prescriptions, medication administration and pharmacy inventory/dispensing
- Service orders, invoices, invoice items, payments and insurance
- HR and payroll
- Maternity, fertility and specialist clinics
- Referrals, care transitions and telemedicine
- Reporting and audit

The contract is intentionally a curated set of minimum operational table/column requirements. It does not claim to prove every business rule, data type, default, nullable rule, FK action, RLS predicate, trigger, RPC body, or complete workflow transition. Those require separate migration replay and runtime integration tests.

## Confirmed live schema mismatch: nursing handover ward association

The canonical `public.nursing_shift_handovers` table has no `ward_id` column, but the deployed `create_nursing_shift_handover` RPC references and inserts that column. The RPC already validates that a supplied ward belongs to the patient's facility. The mismatch means the RPC's INSERT cannot succeed against the inspected table, even when the UI omits the optional ward argument.

A forward-only proposed migration exists at:

`supabase/migrations/20261125090000_restore_nursing_handover_ward_link.sql`

It adds a nullable UUID column, FK to `public.ward_units(id)` with `ON DELETE SET NULL`, and an index. It does not rewrite historical migrations or replace the RPC. **This migration has not been applied to the canonical database** and must pass a clean PostgreSQL 17/Supabase replay before any deployment.

## Security and performance follow-up from current advisors

The current canonical advisors reported:

- Two RLS-enabled tables with no policies: `public.lab_test_groups` and `public.lab_test_group_items`. Their grants and intended access model require review before policies are introduced.
- `public.ensure_updated_at()` has a mutable search path.
- 279 SECURITY DEFINER functions are executable by `authenticated`. These require function-by-function authorization review; a blanket revoke would risk breaking intended workflows.
- 12 tables have multiple permissive policies for the same role/action.
- `public.lab_result_attachments` has a duplicate-index pair.

These are security/performance work items, not evidence that all those tables are missing. No blanket policy, grant, function, or index changes were made.

## Migration and release safeguards

1. Keep canonical database access read-only while migration provenance and replay are unresolved.
2. Keep migration identity validation enabled. Do not rename/delete/reorder the 21 duplicate migration-version groups to make CI green.
3. Keep the hosted migration ledger snapshot distinct from missing historical SQL source files.
4. Require the Quality workflow's typecheck and module-schema contract to pass after every schema/type change.
5. Require clean PostgreSQL 17/Supabase migration replay, catalog parity, RLS/security review, and workflow-level integration tests before promoting any DDL.
6. Generate and commit TypeScript database types from the authoritative environment after reviewed schema changes; never hand-edit generated type declarations to hide schema drift.
7. Treat any new module as incomplete until its table/column contract, relationships, indexes, RLS model, RPC signatures, and end-to-end workflow tests are added.

## Current limitations

- The original canonical baseline SQL source remains unavailable in the repository, so exact historical origin of some schema differences cannot be established.
- The proposed handover repair has not been applied or replay-tested against a disposable PostgreSQL 17/Supabase database.
- The latest Quality run after the generated-type refresh and new module contract is still running at the time this report is committed.
- The migration-contract workflow remains blocked by the previously documented duplicate migration-version groups; do not interpret this audit as migration replay approval.
