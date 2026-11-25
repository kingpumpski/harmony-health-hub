# Migration collision review: 20260914150000

Updated: 2026-11-25

## Scope and decision

Reviewed both candidates sharing version `20260914150000` against canonical PostgreSQL ACLs, RLS, table relationships, and current admission/bed/nursing/insurance RPCs:

- `20260914150000_admission_bed_direct_mutation_reconciliation.sql`
- `20260914150000_clinical_claim_nursing_direct_mutation_hardening.sql`

The canonical database already has authenticated direct DML revoked on encounters, admissions, the legacy `beds` table, and `ward_beds`; the live schema also has the server-side admission, discharge, bed placement, transfer and release workflows that the candidate comments describe as future work. Insurance claim DML is revoked and nursing care-plan INSERT is revoked. The remaining nursing update/delete gaps are documented separately.

**Disposition:** preserve both candidates. Do not replay the old comments or assume that the migration group is fully reconciled. No canonical SQL was applied.

## A. Admission and bed direct-mutation reconciliation

Canonical ACL checks confirm authenticated users have SELECT but no INSERT/UPDATE/DELETE on:
- `encounters`
- `admissions`
- `beds` (legacy table)
- `ward_beds`

All four tables have RLS enabled. The live database has authenticated-only SECURITY DEFINER workflows for:
- encounter creation and completion;
- admission creation;
- discharge;
- ward-bed creation, assignment, release, status changes and patient transfer.

The live `create_admission_workflow` uses a patient-scoped advisory transaction lock, checks active admission duplication, validates patient/ward/bed facility alignment, and routes placement through `transfer_patient_ward_bed_workflow`. The transfer workflow locks the admission and beds, verifies facility equality, updates both bed and admission state, writes movement and care-transition records, and audits the event. Discharge locks the admission and bed, is retry-aware, releases the bed into cleaning, creates a billing handoff notification and records an audit event.

The candidate comments say admissions and beds are locked down "until dedicated ... RPCs are introduced." That statement is stale relative to the current canonical system. The RPCs now exist; keep the direct-DML revocation but update future documentation to reflect the live workflow.

### Important remaining relationship and retention risks

- `ward_beds.admission_id` still lacks a declared FK to `admissions.id`. The transfer/discharge workflows validate and lock the linked records, but the schema does not independently enforce referential integrity.
- `admissions.patient_id` uses ON DELETE CASCADE. A physical patient deletion can cascade into admission history, which is a clinical-record retention risk. Define archive/retention rules before allowing patient hard deletion.
- The legacy `beds` table and current `ward_beds` table coexist. Both have authenticated DML revoked, but the legacy table's remaining consumers and deprecation status should be established before any removal or synchronization work.

## B. Clinical claims and nursing mutation hardening

Canonical ACL checks confirm:
- `insurance_claims`: authenticated INSERT/UPDATE/DELETE revoked.
- `nursing_care_plans`: authenticated INSERT revoked, but UPDATE and DELETE remain granted.
- `ward_units`: authenticated INSERT revoked.
- `nursing_shift_handovers`: authenticated INSERT/UPDATE/DELETE remain granted.

The clinical-claim candidate therefore matches the live insurance and ward-unit boundaries, and the INSERT part of the nursing care-plan restriction is in place. It does not resolve the broader nursing UPDATE/DELETE and handover DML exposure identified in the `20260912250000` review.

The live `create_discharge_insurance_claim` RPC is accountant/admin-only, locks the handoff notification, serializes by admission, reconciles discharge billing, prevents duplicate active claims for the invoice/payer and records an audit event. The live `reconcile_insurance_claim_to_invoice` is also role-checked and row-locked.

The live `create_nursing_care_plan`, `create_nursing_shift_handover`, and `acknowledge_nursing_handover` functions enforce clinical role and patient/facility context. However, create/acknowledge RPCs do not replace all possible direct update/delete operations. The handover creation RPC still references `ward_id`, whose forward repair is staged but unapplied. Do not revoke the remaining handover INSERT compatibility path until that schema dependency and RPC have passed disposable replay and verification.

## Required next actions

1. Preserve the authenticated DML revocations on encounters, admissions, legacy beds, ward beds, insurance claims and ward-unit creation.
2. Update stale candidate comments/documentation only in a new forward migration or a clearly scoped source-provenance note; do not rewrite historical migration files.
3. Add the missing `ward_beds.admission_id -> admissions.id` FK only after a fresh orphan check, explicit delete behavior review, and disposable replay. Prefer retention-safe semantics; do not cascade-delete admission history.
4. Define patient archive/retention behavior before changing patient FK delete actions.
5. Inventory all legacy `beds` table consumers and determine whether it is a read-only compatibility surface or a deprecated duplicate.
6. Complete nursing care-plan update/archive and handover edit/archive RPCs, migrate all UI callsites, fix the pending `ward_id` schema dependency, then revoke remaining authenticated nursing DML.
7. Add ACL tests for direct table mutation denial and positive tests for every supported lifecycle RPC.
8. Test concurrent admission creation and bed placement to confirm patient locks and bed row locks prevent double admission/occupancy.
9. Validate clean bootstrap and upgrade-from-hosted-baseline on disposable PostgreSQL 17/Supabase.

## Execution boundary

All inspection was read-only. No admission, patient, bed, nursing, or claim row contents were queried. No privileges, policies, functions, triggers, constraints, or migration ledger entries were changed. No historical migration was renamed, replayed, applied, or deleted. The collision remains unresolved.
