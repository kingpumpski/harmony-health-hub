# Migration collision review: 20260915170000

Updated: 2026-11-25

## Scope and decision

Reviewed both candidates sharing version `20260915170000` against canonical function ACLs and insurance-claim indexes:

- `20260915170000_reassert_internal_security_definer_execute_hardening.sql`
- `20260915170000_remove_duplicate_insurance_claim_indexes.sql`

The internal-function execution lockdown is already reflected exactly in the canonical ACLs. The index cleanup candidate refers to index names that are absent from the live database; current indexes use different names.

**Disposition:** preserve both originals. The first candidate's intended final state is verified live. The second is a no-op against the inspected canonical catalog and does not prove that duplicate indexes are currently present or removed.

## A. Internal SECURITY DEFINER execution boundary

The canonical database confirms all three functions exist as SECURITY DEFINER routines with pinned `pg_catalog, public` search paths:
- `audit_patient_change()`
- `notify_due_medications()`
- `lock_overdue_medication_slots()`

Their current ACLs grant EXECUTE only to `postgres` and `service_role`. Both anon and authenticated are denied. This matches the candidate's intended restriction. The functions remain available to their trusted trigger/scheduler/server contexts.

**Disposition:** no additional canonical change is indicated for these three functions. Add a regression test to ensure future function replacements do not restore PUBLIC/anon/authenticated EXECUTE.

## B. Insurance claim index cleanup

The candidate drops:
- `insurance_claims_invoice_id_idx`
- `insurance_claims_patient_id_idx`

Neither name exists in the canonical database. The live table instead has:
- `idx_insurance_claims_invoice_id` on `invoice_id`
- `idx_insurance_claims_patient_id` on `patient_id`
- `insurance_claims_facility_id_idx`
- `insurance_claims_invoice_active_unique_idx` (partial unique index)
- status, company and primary-key indexes.

The current catalog has only one ordinary index on `invoice_id` and one on `patient_id`; the candidate's two `DROP INDEX IF EXISTS` statements would do nothing against this schema. The partial unique invoice index is not a duplicate of either ordinary lookup index: it enforces one non-voided/non-rejected claim per invoice.

**Disposition:** do not rename/drop the live indexes to match the candidate. If an index-performance cleanup is still required, compare index definitions, predicates, operator classes, constraints, query plans and workload usage first. Preserve the partial unique constraint.

## Required next actions

1. Add a function ACL regression contract asserting these internal SECURITY DEFINER routines remain executable only by postgres/service_role.
2. Inventory every trigger and scheduler dependency before modifying these functions.
3. Keep the current invoice and patient lookup indexes; verify index usage and duplicate definitions before any drop.
4. Treat the candidate index names as historical drift, not as evidence of live duplicates.
5. Reconcile both migration source histories and hosted ledger identities before any collision repair.
6. Test clean bootstrap and hosted-upgrade paths separately on disposable PostgreSQL 17/Supabase.

## Execution boundary

All inspection was read-only. No clinical or insurance claim row contents were queried. No SQL, ACL, index, function, trigger, or migration ledger entry was changed. No historical migration was renamed, replayed, applied, or deleted. The collision remains unresolved.
