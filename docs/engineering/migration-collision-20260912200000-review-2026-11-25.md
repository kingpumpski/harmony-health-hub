# Migration collision review: 20260912200000

Updated: 2026-11-25

## Scope and decision

Reviewed the two candidates sharing version `20260912200000` against the live canonical database:

- `20260912200000_phase5_lab_catalogue_and_audit.sql`
- `20260912200000_prescription_payment_lifecycle_reconciliation.sql`

Both tracks have live schema/workflow counterparts. The lab candidate is a historical catalogue/audit foundation; the prescription candidate describes a payment-to-prescription status bridge that is **not currently installed** in the canonical database. Preserve both originals; do not select, rename, or replay either based only on the shared timestamp.

## A. Laboratory catalogue and patient audit

The live database contains `lab_test_catalogue`, `lab_test_catalog`, `lab_test_parameters`, `lab_orders`, `lab_results`, and `patient_audit_log`. The canonical lab catalogue has evolved and is managed through permission-checked SECURITY DEFINER RPCs such as `create_lab_test_catalogue_item_with_parameters`; it stores structured parameter metadata and uses current field names. The candidate's table definition and seed assumptions are not a safe replacement.

The live `lab_test_catalogue` already has:
- authenticated read access for active catalogue items (admin can read inactive entries);
- admin-only direct insert/update/delete policies;
- an operational row-change audit trigger.

The candidate seeds six tests, including fixed reference text and a numeric fasting-glucose interval. Those values must not be promoted as universal clinical ranges. Laboratory reference intervals and specimen/parameter metadata must be approved and maintained by the responsible laboratory, with appropriate age/population and method context. Keep the catalogue empty or incomplete rather than silently publishing unvalidated clinical ranges.

The candidate creates `patient_audit_log` with patient ON DELETE CASCADE and adds a staff-read policy. The live table has evolved: the patient FK uses ON DELETE SET NULL, and a patient trigger writes to it. The live patient audit log also has a separate admin mutation policy, which merits a distinct audit-integrity review; do not replace the live retention semantics with CASCADE.

## B. Prescription payment lifecycle

The candidate defines two triggers:
- invoice-item payment changes update prescription status to `paid` when aggregate payments reach the item amount;
- dispensing-plan status changes update prescription status to `dispensed` or `cancelled`.

These functions and triggers are **absent** from the canonical database at inspection time. The current prescription creation RPCs are encounter- and facility-scoped, and the canonical pharmacy dispensing plan table has facility-lineage enforcement, but there is no database trigger with these candidate names to synchronize invoice payment and dispensing status.

The candidate is therefore a potentially useful missing workflow capability, not a migration that has already been applied. It is not ready to apply unchanged:

1. It maps a pharmacy invoice item to a prescription through `service_orders.related_entity_id` or `invoice_items.source_id`. Both columns exist, but the mapping must be validated against actual pharmacy invoice-item creation paths, including service-order links and legacy invoice rows.
2. The payment trigger handles INSERT and UPDATE OF amount, but not DELETE of a payment row or any separate reversal/refund lifecycle. A paid prescription could remain paid after a payment is removed or reversed.
3. It compares SUM(payment rows) to invoice item amount. The canonical `invoice_items` also has `paid_amount` and payment reconciliation fields; establish which amount is authoritative and ensure refunds, voids, insurance allocations, and overpayments are handled consistently.
4. It does not lock the invoice item/prescription while recalculating. Concurrent partial payments and dispensing transitions need transaction-level tests and a deterministic state reconciliation rule.
5. It changes prescription status directly to `paid` and `dispensed`; inspect the existing prescription status state machine, dispensing-plan lifecycle, and UI/RPC consumers before introducing this bridge.
6. The trigger's `UPDATE OF amount` semantics and the AFTER INSERT/UPDATE payment event must be tested with multiple payment rows and rollback behavior. A single trigger invocation must not leave a stale prescription status.
7. Any payment-to-prescription linkage must enforce patient and facility equality across invoice item, service order, prescription, and dispensing plan. Do not trust a matching UUID alone.

## Required next actions

1. Inventory invoice item creation and payment/reversal/refund RPCs and map the canonical relation from pharmacy order to prescription.
2. Design a single authoritative payment-state reconciliation function that can be safely called after insert, update, delete, reversal, and void events, with row locks and idempotent state transitions.
3. Define whether a paid prescription can return to pending/unpaid after a refund and whether dispensing is reversible; obtain pharmacy and finance governance approval.
4. Add integration tests for partial payments, concurrent payments, overpayment, refund/reversal, invoice edits, cancellation, and dispensing status.
5. Preserve facility checks across every relation and ensure only the intended pharmacy/finance roles can cause each transition.
6. Keep the existing lab catalogue RPC and current catalogue schema; require laboratory sign-off for reference intervals and test metadata.
7. Reconcile source provenance and later migrations before assigning a unique identity to either historical candidate.
8. Test clean bootstrap and upgrade-from-hosted-baseline on disposable PostgreSQL 17/Supabase.

## Execution boundary

All database inspection was read-only. No patient, prescription, invoice, or laboratory result content was queried; only schema, function, trigger, policy and aggregate metadata were inspected. No SQL was applied and no migration file was changed.
