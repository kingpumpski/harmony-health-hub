# Appointment Concurrency and Clinical State Hardening

## Scope

The canonical appointment workflow now has a final server-authoritative concurrency and state-transition boundary. No second appointment subsystem is introduced.

## Controls

- Appointment creation requires an authenticated authorized operational role, a valid patient, and a department.
- Merged patient records cannot receive new appointments.
- Concurrent requests for the same patient and scheduled timestamp are serialized with a transaction-scoped advisory lock before duplicate detection.
- Active duplicate appointments for the same patient/time are rejected while completed, cancelled and no-show history remains reusable.
- Appointment claiming is atomic and can only assign an unclaimed/open appointment or preserve an existing claim by the same officer.
- Closed appointments cannot be claimed.
- Appointment updates lock the row with `FOR UPDATE` before authorization and transition checks.
- Front-desk users are restricted to operational scheduling/cancellation/no-show changes and cannot perform clinical treatment-state transitions.
- Clinical officers must own the appointment before changing its clinical treatment state.
- The clinical lifecycle is monotonic for non-admin users: `scheduled -> claimed -> in_progress -> completed`; cancellation/no-show are controlled terminal exits.
- In-progress appointments cannot be moved backward by ordinary clinical users.
- Encounter creation locks the appointment and requires the assigned clinical officer (or an administrator).
- Closed appointments cannot start new encounters.
- Direct authenticated appointment table mutation remains revoked.
- The existing canonical clinical audit trigger remains the audit surface.

## Evidence

Executable repository contract checks are provided by `scripts/test-nextgen-appointment-concurrency.mjs` and are part of the Quality workflow.

Live PostgreSQL/RLS execution remains a separate promotion gate because the correct active Harmony Supabase project is not currently connected. The implementation therefore does not claim live migration replay or RLS verification.
