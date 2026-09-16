# Admission and Bed Concurrency Integrity

## Purpose

This boundary makes inpatient admission and ward-bed occupancy server-authoritative while reusing the canonical `admissions`, `ward_beds`, and `ward_units` tables.

## Controls

- Admission creation requires an authenticated authorized clinical role.
- A patient cannot have two active admissions.
- A requested bed is selected and row-locked before the admission is inserted.
- Only an available, unoccupied bed in the requested ward unit can be attached to an admission.
- Admission creation and bed occupancy are committed in one transaction.
- Bed assignment row-locks the target bed and validates patient/admission ownership.
- An admission cannot acquire a second bed through the assignment workflow.
- Discharge row-locks the admission and releases its linked bed into `cleaning` atomically.
- An occupied bed with an active admission cannot be manually released.
- Direct authenticated INSERT/UPDATE/DELETE access to admission and bed tables remains disabled.
- Public and anonymous execution of lifecycle RPCs is revoked.
- Existing ward/bed infrastructure and UI RPC names are preserved; no parallel inpatient service is introduced.

## Verification

`test-nextgen-admission-bed-concurrency.mjs` checks the server-authoritative workflow, row locking, active-admission protection, bed availability, admission/bed linkage, direct-write lockdown, and Quality workflow wiring.

Live migration replay and RLS execution remain dependent on access to the correct active Harmony Supabase project. Contract tests therefore do not substitute for eventual database replay and concurrency testing.
