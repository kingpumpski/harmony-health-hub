# Open PR Recovery Matrix — 2026-11-03

## Purpose and operating rule

This matrix prevents the 19 currently open pull requests from being treated as 19 independent merge jobs. Shared migration and security defects are repaired in the canonical integration branch, while independent features remain isolated until their schema prerequisites and integration checks pass.

**No PR is approved for merge by this document.** Do not merge, close, or mark a PR superseded until the final-head checks pass and the evidence below is revalidated.

## Current integration state

- Canonical recovery branch: `integration/migration-reconciliation` (PR #442).
- Production migration baseline remains `unreconciled`; production database push is prohibited.
- The live database was inspected read-only. It reports `update_insurance_claim_financials(uuid,numeric,numeric,text,text)` returning `insurance_claims`; the clean-replay migration must preserve that return type.
- Live `seed_facility_reports(uuid)` returns `void`; `recover_stale_report_run(uuid,integer)` returns `report_generation_runs`; `upsert_report_submission_tracking(...)` returns `report_submissions`.
- Live HR archive columns `archived_at` and `archived_by` exist, and the production migration ledger includes `20261026134619_reconcile_hr_payroll_record_management`.
- Live laboratory read RPC privileges were verified: both `get_laboratory_test_groups(boolean)` and `get_lab_result_attachments(uuid[])` deny `anon` and allow `authenticated`.

## PR dispositions

| PR | Scope | Recovery disposition |
|---|---|---|
| #442 | Canonical migration reconciliation | Keep as the integration workstream. It owns the combined migration, schema, security, and CI repair. Do not merge until clean replay and all required final-head checks pass. |
| #440 | PL/pgSQL dollar-quote repair | The tagged `$claim_financials$` terminator is present and verified in the integration migration. Its branch is heavily diverged; do not merge wholesale. |
| #439 | Insurance-claim financial RPC return type | Do not port the branch's `JSONB` return type: live production and integration use the `insurance_claims` composite return. The integration migration also has the tagged dollar-quote terminator. |
| #438 | JSON/FHIR, XML and HL7 clinical staging imports | Independent feature. Rebase/port after migration recovery; preserve staging-only behavior and rerun parser regression, Quality, and migration replay. |
| #437 | Broad clean-replay and schema reconciliation | Heavily diverged, with local CLI state and reconciliation evidence mixed into its file set. Select only individually reviewed fixes; never merge the branch wholesale. |
| #436 | Facility reconciliation lineage | Its migration `20260930015100_extend_facility_reconciliation_inventory.sql` is already present in the integration branch. Recheck its contract during the final replay. |
| #434 | Migration prerequisites and policy replay | Heavily overlapping and diverged. Use as a source of candidate fixes only; port individual missing prerequisites after proving the first replay failure. |
| #433 | Emergency acuity compatibility | The forward-compatible `20261021100000_reconcile_emergency_case_acuity.sql` migration has been ported to integration and given a contract assertion. |
| #432 | Hospital-wide HIMS completion blueprint | Documentation-only draft. Keep separate from database recovery; review and rebase independently. |
| #429 | Laboratory RPC anon execution | Live grants are already correct. An idempotent final reconciliation migration has been added to integration to preserve authenticated-only execution on clean replay. |
| #428 | Preview auth storage lint | Single-file branch. Integration currently uses `const` for the timeout; the branch's only observed difference is statement ordering. Do not port unless the final Quality run demonstrates a real failure. |
| #427 | Prescription timestamp/schema drift | Broadly diverged branch with substantial unrelated changes. Inspect the specific prescription migration and its schema dependency against integration before any selective port. |
| #426 | HR employee archive columns | Live columns exist and the production ledger records the HR/payroll reconciliation migration. Do not add a duplicate historical migration; verify the clean-replay HR contract. |
| #423 | Role-aware financial UI | Independent UI feature with a new financial overview access migration. Hold until migration recovery is stable, then review authorization boundaries and rebase separately. |
| #422 | Laboratory legacy schema reconciliation | Broadly diverged and overlaps #398/#420. Select only missing schema/contract changes after comparing against integration and the live schema. |
| #421 | Future-proof migration contracts | Integration already contains coordinated migration contracts and CI gates. Review for unique safeguards only; do not merge its divergent migration history wholesale. |
| #420 | Laboratory panel migration | Overlaps the laboratory schema work in #398/#422. The panel migration is present in integration; validate the related contract rather than merging the stale branch. |
| #398 | Laboratory APIs and result approval | Large overlapping feature/security branch. Core laboratory migrations are present in integration; review any missing UI, RPC, or test changes individually after clean replay. |
| #18 | Next-generation HIMS reference platform | Separate draft architecture/reference implementation. Keep isolated; no direct merge into the canonical production application. |

## Active migration defects found during clean replay

1. The outside-lab policy referenced `radiologist` before that enum value existed. The isolated role migration now adds it before the policy migration, with a contract assertion.
2. `seed_facility_reports(uuid)` was first created as `RETURNS INTEGER`, then replaced as `RETURNS VOID`. The Reports Center hardening migration now explicitly drops the earlier signature before recreating the production `VOID` contract.
3. `recover_stale_report_run(uuid,integer)` was first created as `RETURNS BOOLEAN`, while the later production reconciliation expects `report_generation_runs`. The reconciliation migration now explicitly drops the earlier signature before recreating the composite-return RPC.
4. `upsert_report_submission_tracking(...)` was first created as `RETURNS INTEGER`, while the later production reconciliation expects `report_submissions`. The reconciliation migration now explicitly drops the earlier signature before recreating the composite-return RPC.
5. The laboratory RPC privilege state was already correct in production but needed an explicit, idempotent migration so clean replay preserves the same boundary.

## Validation gates

- Static migration contract passes on the exact latest integration SHA.
- Clean Supabase startup and full migration replay pass from an empty local database.
- Database contract SQL passes, including RPC signatures, grants, RLS, schema advisor remediation, HR/payroll compatibility, and consolidated RLS paths.
- Quality passes: typecheck, lint, tests, and production build.
- Production migration provenance is reconciled with evidence for every baseline entry; only then may a separately approved production deployment plan be prepared.

A failed or cancelled run is not a pass. Never weaken a check or mark a blocker resolved just to allow a merge.
