# Migration collision review: 20260913180000

Updated: 2026-11-25

## Scope and decision

Compared the two candidates sharing version `20260913180000` with the live canonical PostgreSQL schema, function bodies, RLS policies, and table privileges:

- `20260913180000_reconcile_appointments_operational_workflow.sql`
- `20260913180000_reports_center_submission_rbac.sql`

Both feature tracks exist in the live database and have evolved. The appointment implementation is materially more facility-aware than the candidate. The report submission RPC exists, but direct table privileges and policies still permit a path that bypasses the RPC's role check.

**Disposition:** preserve both candidate files; do not replay the appointment function bodies unchanged. The report submission RBAC is only partially enforced and needs a separate forward repair after confirming UI callsites.

## A. Appointment workflow reconciliation

The live `appointments` table contains the candidate's core fields (`attending_officer_id`, `claimed_at`, `treatment_status`, `treatment_notes`, `started_at`, `completed_at`) plus later compatibility fields such as `appointment_date`, `provider_id`, `consultation_type`, and `facility_id`.

The canonical database has two overloads of `create_appointment_workflow`, a hardened `claim_appointment`, a hardened `update_appointment_workflow`, and a facility-filtered appointment worklist. The live functions use pinned search paths, require authenticated roles, validate patient facility, and include test-facility isolation in the claim workflow. The candidate's original bodies use `SET search_path=public` and do not enforce these controls. Replaying the candidate bodies could regress security.

### Remaining appointment workflow gaps

1. **No clinician schedule-overlap/capacity enforcement was found in the inspected create/claim/update functions.** Concurrent requests can create conflicting appointments or overbook a clinician because there is no clinician/day lock, exclusion constraint, or atomic availability reservation in these functions.
2. The creation functions set a fixed 30-minute duration and do not consult a clinician schedule or configurable appointment type duration.
3. The four-argument overload performs a direct patient facility lookup and active-facility comparison but does not call the shared `assert_patient_facility_context` helper. The six-argument overload does call the helper. Consolidate to one authoritative implementation or ensure both overloads enforce identical test-user and patient-state rules.
4. The six-argument overload checks that a practitioner profile exists but does not verify that the selected practitioner is active, has the practitioner role, or is assigned to the target facility.
5. The update workflow checks facility context and assignment but does not enforce a complete state-transition graph or reject schedule changes that conflict with another appointment.
6. The inspected appointment workflow functions do not visibly emit an audit event for create, claim, reschedule, or completion. Confirm whether the live audit trigger covers all required fields; add explicit workflow audit events if the trigger is insufficient.
7. Appointment SELECT policy includes patient self-access by user ID/email. Ensure all staff RPCs and direct table paths continue to enforce facility scope and patient ownership appropriately.

**Disposition:** retain the hardened live functions. Build a unified scheduling service with facility-aware clinician availability, transaction-scoped conflict protection (e.g. exclusion constraints or deterministic provider/time locks), idempotency, test-facility isolation, and explicit audit events. Do not add a simple pre-insert overlap SELECT without concurrency protection.

## B. Reports Center submission RBAC

The live `mark_report_submissions_submitted(uuid[])` RPC exists and is stronger than the candidate in some respects:
- requires an authenticated caller;
- restricts role to admin, practitioner, nurse, midwife, or specialist nurse;
- filters updates by `has_facility_access`;
- only transitions pending/overdue rows to submitted;
- has a pinned `pg_catalog, public` search path.

The canonical `report_submissions` table has RLS enabled, but authenticated users still have direct INSERT and UPDATE table privileges. Its policies allow:
- INSERT when the caller has facility access to the supplied `facility_id`;
- UPDATE when the caller has facility access and the existing `submitted_by` is null, matches the caller, or caller is admin; the new row only has to remain in a facility the caller can access.

These policies do **not** enforce the same operational-role allowlist as `mark_report_submissions_submitted`. A facility member with a less privileged role can therefore use direct PostgREST INSERT/UPDATE to create or alter report submission rows without going through the RBAC-checked RPC. The RPC's role guard does not protect the direct table path.

**High-priority forward repair:** inventory report-center UI callsites, add or verify server RPCs for create/update/draft/finalize/submit, then revoke direct authenticated INSERT/UPDATE (and any unneeded DELETE) on `report_submissions`. Preserve authenticated SELECT with facility-aware RLS. Test allowed and denied roles and facility boundaries. Do not revoke before confirming all UI writes use the server path.

## Required next actions

1. Unify appointment creation overloads so they share patient status, test-user, facility, and practitioner validation.
2. Add a concurrency-safe clinician availability/overlap mechanism, with tests for two simultaneous bookings for the same clinician and time range.
3. Add configurable appointment duration and enforce clinician facility/active status.
4. Verify appointment audit coverage for create, claim, reschedule, no-show, cancel, and completion.
5. Move Reports Center writes behind authenticated role-checked RPCs, then revoke direct authenticated table mutation after callsite reconciliation.
6. Add ACL/RLS regression tests that prove non-reporting roles cannot create or modify submissions even if they have facility access.
7. Preserve live function safe search paths and do not restore candidate definitions.
8. Reconcile hosted ledger provenance and subsequent migration dependencies before assigning unique migration identities.
9. Validate clean bootstrap and upgrade-from-hosted-baseline on disposable PostgreSQL 17/Supabase.

## Execution boundary

All inspection was read-only. No appointment, patient, or report submission row contents were queried. No SQL, table privileges, RLS policies, functions, triggers, or migration ledger entries were changed. The collision remains unresolved.
