# Nursing Continuity and Care-Plan Integrity

## Scope

This boundary hardens the canonical `nursing_care_plans` and `nursing_shift_handovers` workflows without introducing replacement tables or a second nursing service.

## Care-plan controls

- Creation requires an authenticated nursing role and a real patient.
- When linked to an admission, the admission must belong to the patient and remain active.
- Priority is constrained to `routine`, `high`, or `critical`.
- Lifecycle transitions lock the care-plan row with `FOR UPDATE`.
- Completed and cancelled plans cannot be reopened.
- Holding or cancelling a plan requires a reason.
- Completion requires an evaluation.
- An admission-linked plan cannot be returned to `active` after the admission has closed.
- Existing clinical audit convergence remains the audit boundary; no parallel audit ledger is introduced.

## Handover controls

- Handover creation requires an authenticated nursing role and a clinical summary.
- Admission linkage is validated against the patient and active admission state.
- The outgoing officer is the authenticated actor.
- The incoming officer defaults to the authenticated actor but can be explicitly designated only when that user exists and holds an authorized nursing role.
- The admission-aware handover UI now loads only active admissions, sends the admission identifier through the next-generation RPC, and no longer relies on the legacy patient-only handover call.
- The explicit clinical shift date is persisted in the canonical `nursing_shift_handovers.shift_date` field; it is not duplicated into a new column or accepted and discarded by the workflow.
- Shift dates are constrained to a narrow operational window around the current date to prevent accidental backdating or future-dated handovers.
- A handover can be acknowledged only by its designated incoming officer or an administrator.
- Acknowledgement locks the handover row before mutation and is idempotent when already acknowledged.

## Security boundary

Authenticated clients cannot directly insert, update, or delete nursing care plans or handovers. They use the server-authoritative lifecycle RPCs. This prevents client-side state changes from bypassing admission continuity, lifecycle, role, or acknowledgement controls.

## Verification

`npm run test:nextgen-nursing-continuity` verifies the migration contract, canonical shift-date usage, persisted shift-date semantics, and admission-linked UI/RPC boundary. Live database replay remains dependent on access to the correct active Harmony Supabase project; the repository test is therefore a contract test, not a substitute for live concurrency testing.
