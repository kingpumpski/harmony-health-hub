# Reports Center and inpatient relationship follow-up — 2026-11-25

## Scope

Read-only inspection of hosted project `ygqoptvezotdqhtimdkr` and application callsites. No database writes, patient-row reads, or deployments occurred.

## 1. Reports Center submission table can be made client-read-only

Live ACL for `public.report_submissions` currently grants authenticated users SELECT, INSERT, and UPDATE; DELETE is already absent. Anon has no table privileges.

Live RLS policies:
- `submissions_access`: authenticated SELECT, facility-scoped through `current_user_has_facility_access(facility_id)`.
- `submissions_insert`: authenticated INSERT, facility-scoped and submitter-attributed.
- `submissions_update`: authenticated UPDATE, facility-scoped and restricted by submitter/admin logic.

Application callsite review of `src/lib/reportsCenter.ts`:
- `listSubmissions()` directly SELECTs `report_submissions` by facility and period.
- `markSubmissionsSubmitted()` uses `mark_report_submissions_submitted(uuid[])`.
- Report generation creates/updates submission tracking through `upsert_report_submission_tracking(...)`.
- No direct client INSERT/UPDATE/UPSERT/DELETE of `report_submissions` was found in the source callsites reviewed.

**Forward repair recommendation**
- Preserve authenticated SELECT and the facility-scoped `submissions_access` policy.
- Revoke authenticated INSERT and UPDATE table privileges.
- Drop `submissions_insert` and `submissions_update` policies so a future accidental grant cannot silently re-enable direct writes.
- Keep submission mutation in the existing SECURITY DEFINER RPCs, after verifying each RPC's exact role/facility checks and signature.
- Add database regression assertions for SELECT allowed, anon SELECT denied, direct authenticated DML denied, and the read policy retained.

Static source contract and pgTAP regression SQL have been added. The pgTAP assertions are expected to fail against the currently inspected hosted INSERT/UPDATE ACL until the forward repair is applied.

## 2. Ward-bed admission relationship

Live catalog inspection confirms:
- `ward_beds.admission_id` is nullable and currently has no FK to `admissions(id)`.
- A read-only orphan query returned **zero** non-null `ward_beds.admission_id` values without a matching admission.
- `ward_beds.patient_id` references patients with `ON DELETE SET NULL`.
- `ward_beds.ward_id` references ward units with `ON DELETE CASCADE`.
- `admissions.patient_id` references patients with `ON DELETE CASCADE`.

The current discharge workflow clears both `patient_id` and `admission_id` when it releases an occupied bed to cleaning. Bed transfer/release workflows also clear `admission_id`. The active occupied bed retains the admission link.

**Forward repair recommendation**
- Add a validated FK from `ward_beds.admission_id` to `admissions.id` with `ON DELETE RESTRICT` (NO ACTION is also acceptable if the migration/transaction semantics are deliberately selected and tested).
- Do not cascade deletion from admissions into a bed record; the bed is a separate operational resource.
- This restrictive FK also prevents a patient-delete cascade from erasing an admission that is still referenced by an occupied bed, while discharged/released beds have already cleared the link.
- Confirm all legacy bed assignment/release paths against the live function definitions before applying.
- Remove the relationship exception from `scripts/module-relationship-exceptions.json` only after the FK is applied, validated, generated types reflect it, and the relationship contract passes.

A pgTAP contract now asserts that the validated FK exists with a restrictive delete rule. It will fail until the forward migration is applied.

## 3. Triage RPC signature mismatch confirmed

The canonical live signature is:

`record_triage_assessment(uuid, integer, integer, integer, numeric, integer, numeric, numeric, numeric, integer, text, text, text, text)`

That is 14 arguments. The historical candidate reviewed earlier references a 15-argument overload for its privilege statement. This is a real signature mismatch, not a missing live triage RPC. Do not replay the candidate unchanged; its function privilege statement can fail because the referenced overload does not exist. Any future privilege repair must use the exact live identity arguments and should be checked against the offline replay RPC separately.

## 4. Repository changes in this continuation

Added:
- `scripts/report-submissions-readonly-contract.mjs`
- `supabase/tests/database/report_submissions_readonly_contract.sql`
- `supabase/tests/database/ward_beds_admission_fk_contract.sql`

Updated:
- `package.json` to include the Reports Center read-only callsite contract in the aggregate test script.
- `.github/workflows/quality.yml` to run that static contract.

## 5. Verification and deployment boundary

- Live ACL, RLS policy, FK, and orphan checks were read-only.
- The new source contract checks that the UI keeps direct SELECT and uses RPCs for writes.
- The pgTAP contracts are committed but have not been replayed against a disposable PostgreSQL 17/Supabase database.
- No local Supabase CLI, PostgreSQL client, Docker, or Podman binary is available in this execution environment.
- No canonical database mutation or deployment was performed.

## Disposition

**Ready for forward migration design:** Reports Center direct-write revocation and restrictive ward-bed admission FK.

**Confirmed:** triage candidate overload mismatch; use the live 14-argument signature.

**Still blocked:** generation of active migrations through Supabase CLI, disposable replay, database tests, advisor re-run, and final CI validation. Historical migration collisions remain unresolved and must not be bypassed.
