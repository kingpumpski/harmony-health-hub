# Billing and insurance claim production error review — 2026-11-25

## Scope and safety

Read-only investigation of the reported billing-window error and the HTTP 400 from
`transition_insurance_claim_canonical` on hosted project
`ygqoptvezotdqhtimdkr`. No patient, claim, invoice, or payment row contents were
read. No production data or schema was changed.

## 1. Billing-window failure: confirmed root cause

Observed production error:

```
function pg_catalog.coalesce(numeric, integer) does not exist
```

The PostgreSQL log identifies the call chain:

- `public.get_billing_window(uuid,timestamptz)`
- `public.prepare_patient_billable_items(uuid,timestamptz,timestamptz)`
- Failure at the invoice-total UPDATE, specifically
  `UPDATE public.invoices SET total_amount=pg_catalog.coalesce((SELECT sum(ii.amount) ...),0)`.

The deployed `prepare_patient_billable_items` definition contains schema-qualified
special SQL expressions: `pg_catalog.coalesce`, `pg_catalog.greatest`, and
`pg_catalog.least`. These are SQL special forms, not callable functions, and must
not be schema-qualified. The function also contains several other occurrences, so
fixing only the first failing expression would expose subsequent failures. A
read-only inventory of all public functions and procedures found this to be the
only live routine containing any of these three invalid qualified special forms.

The repository already contains
`20261013150000_fix_billing_window_special_form_qualification.sql`, which
rewrites all three forms in the live function definition. However:

- The hosted migration ledger has no `20261013150000` entry.
- Hosted latest migration remains `20261026141054`.
- The live function still contains the invalid expressions.

Therefore the historical repair was not applied to this canonical project. Do not
edit or backfill that historical migration identity. Prepare a new forward-only
migration with a version later than `20261026141054`, generated through
`supabase migration new`, and include a fail-closed definition check plus a
post-migration catalog assertion that no invalid qualified forms remain. Keep the
function's existing SECURITY DEFINER setting, empty search_path, signature,
return shape, and grants unchanged. Verify execution on disposable PostgreSQL 17
before any hosted deployment.

## 2. Insurance-claim HTTP 400: confirmed data-lineage blocker

The deployed RPC exists with the expected identity:

`transition_insurance_claim_canonical(uuid,text,numeric,numeric,text,text)`

It is SECURITY DEFINER, has `search_path = 'pg_catalog, public'`, grants
EXECUTE to `authenticated`, and denies it to `anon`. The current function checks
authentication, admin/accountant role, patient facility context, claim-to-patient
facility equality, invoice-to-patient/facility consistency, and legal state
transitions.

The PostgreSQL logs show the actual 400 cause:

```
Insurance claim facility does not match patient facility
```

The same error occurred twice within the observed log window. This is not a
PostgREST argument-name or function-signature mismatch.

Read-only aggregate lineage checks found one claim in the table:

- Its patient exists and has a facility.
- The claim's `facility_id` is NULL.
- Its linked invoice exists and references the same patient.
- The invoice's `facility_id` is also NULL.
- Thus claim and invoice both lack facility attribution, and the RPC correctly
  refuses to transition the claim.

Do not simply copy the patient's current facility onto the claim and invoice:
current patient assignment alone does not prove the facility that owned the
historical financial transaction when it was created. First reconcile authoritative
facility lineage from claim/invoice creation context and audit history. If the
historical facility cannot be established, route the record to an authorized
finance/data-steward reconciliation queue; do not weaken the RPC's facility check.

## 3. Required follow-up implementation

1. Generate a new forward migration after the hosted baseline to repair the billing
   special-form qualification and assert the resulting function body.
2. Add a regression test that executes the invoice-total path and the accommodation
   date-range path, not merely a string check. Include mixed numeric/integer
   COALESCE operands and NULL cases.
3. Add an aggregate integrity contract for claims and invoices requiring facility
   attribution to match their patient and each other, while supporting an explicit
   exception/reconciliation workflow for legacy unresolved records.
4. Add a safe finance reconciliation workflow for unresolved claim/invoice facility
   lineage. Require an authorized actor, evidence/reason, audit event, and
   transactional consistency; do not auto-backfill from current patient assignment.
5. Keep the insurance transition RPC's facility guard and state machine intact.
   Add regression tests for matching facility, NULL claim facility, NULL invoice
   facility, cross-facility mismatch, and valid/invalid status transitions.
6. Continue the previously prioritized maternity, department-queue, pharmacy,
   patient-audit, and operational-workspace facility-boundary reviews. Do not
   introduce broad data backfills or loosen SECURITY DEFINER boundaries.

## Verification status

- Confirmed root cause for billing-window failure from hosted PostgreSQL logs and
  live function definition.
- Confirmed reason for insurance-claim 400 from hosted PostgreSQL logs.
- Confirmed historical billing repair migration absent from hosted ledger.
- Read-only catalog and aggregate checks completed.
- No migration applied; no production row updated.
- Disposable replay and full Quality/CI verification remain pending.

## 4. Added deployed-function regression gate — 2026-11-25

The repository now has a separate pgTAP catalog contract at
`supabase/tests/database/billing_window_special_forms_contract.sql`. It targets
the exact deployed `prepare_patient_billable_items(uuid,timestamptz,timestamptz)`
identity and asserts that its catalog definition contains none of the three
invalid qualified special forms.

The Node source contract
`scripts/billing-window-special-forms-database-contract.mjs` verifies that the
SQL test keeps the exact function identity and all three negative assertions.
It is registered as
`test:billing-window-special-forms-database-contract` and included in the
Quality workflow after the existing migration-source contract.

A fresh read-only catalog check on the canonical hosted project still reports
all three invalid forms present, so the new database assertion is expected to
fail until a forward repair is applied. This is intentional: the test must not
pass merely because the migration text looks correct.

Verification boundary: the new Node source contract has not yet been executed
in a local checkout, the pgTAP contract has not been run against a disposable
PostgreSQL 17 database, and no CI run for the latest branch head is available.
No hosted migration or production change was made.
