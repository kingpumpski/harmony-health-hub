# Billing materialization special-form repair — 2026-11-27

## Finding

The repository's `prepare_patient_billable_items(uuid,timestamptz,timestamptz)` definition in `20261006170000_reconcile_encounter_completion_billing_materialization.sql` qualifies SQL special forms as if they were ordinary catalog functions: `pg_catalog.coalesce(...)`, `pg_catalog.greatest(...)`, and `pg_catalog.least(...)`. These are SQL special forms and must not be schema-qualified. The historical correction migration `20261013150000_fix_billing_window_special_form_qualification.sql` contains a source-level repair, but the historical ledger reconciliation has not established that this migration ran in every environment.

## Forward-only correction

Added `20261127100700_fix_billing_window_special_form_qualification.sql` as a forward-only, guarded repair:

- Resolves the exact existing three-argument RPC by `regprocedure`.
- Does nothing when all three qualified forms are already absent.
- Replaces all three forms when the complete known defect is present.
- Aborts on partial/unexpected source drift rather than applying a partial text rewrite.
- Replaces the retrieved function definition, preserving the existing function identity, return shape, owner and ACLs while retaining the source definition's security attributes.

The existing database contract `billing_window_special_forms_contract.sql` continues to pin the 14-column return shape, three-argument signature, SECURITY DEFINER mode, empty search_path, and authenticated/service-role versus PUBLIC/anon execution expectations.

## Verification scope

Added `scripts/billing-window-special-form-forward-repair-contract.mjs` to `npm run test:migration-parity`. This static contract verifies the migration's exact RPC target, idempotent no-op, fail-closed drift guard, replacement tokens, and linkage to the deployed database contract.

This is source-level verification only. No PostgreSQL instance was started, no database function was inspected or executed, and no database was modified. The existing 21 duplicate historical migration timestamp groups still prevent clean replay at migration identity preflight. The forward repair remains staged for review and must not be treated as deployed until replay and database contract tests pass in an explicitly identified disposable test environment.
