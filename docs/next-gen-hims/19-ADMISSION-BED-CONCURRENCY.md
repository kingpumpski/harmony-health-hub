# Admission and Bed Concurrency Integrity

## Purpose

This boundary makes inpatient admission and ward-bed occupancy server-authoritative while reusing the canonical `admissions`, `ward_beds`, and `ward_units` tables.

## Controls

- Admission creation requires an authenticated authorized clinical role.
- Admission creation takes a transaction-scoped advisory lock keyed to the patient before checking for an active admission, preventing two concurrent admission requests from both passing the duplicate check.
- A patient cannot have two active admissions.
- A requested bed is selected and row-locked before the admission is inserted.
- Only an available, unoccupied bed in the requested ward unit can be attached to an admission.
- Admission creation and bed occupancy are committed in one transaction.
- Bed assignment row-locks the target bed and validates patient/admission ownership.
- The ward-bed UI now resolves the patient's active admission before assignment and sends that admission ID to the server workflow; patients without an active admission are not offered as inpatient bed-assignment choices.
- An admission cannot acquire a second bed through the assignment workflow.
- Discharge row-locks the admission and releases its linked bed into `cleaning` atomically.
- Discharge is blocked while an admission-linked nursing care plan remains `active`; the care plan must first be explicitly completed or cancelled through its nursing lifecycle RPC.
- An occupied bed with an active admission cannot be manually released.
- Direct authenticated INSERT/UPDATE/DELETE access to admission and bed tables remains disabled.
- Public and anonymous execution of lifecycle RPCs is revoked.
- Existing ward/bed infrastructure and UI RPC names are preserved; no parallel inpatient service is introduced.

## Verification

`test-nextgen-admission-bed-concurrency.mjs` checks the server-authoritative workflow, patient-level concurrency serialization, row locking, active-admission protection, bed availability, admission/bed linkage, nursing care-plan discharge gate, ward-board admission resolution, admission-aware bed assignment, direct-write lockdown, and Quality workflow wiring.

Live migration replay and RLS execution remain dependent on access to the correct active Harmony Supabase project. Contract tests therefore do not substitute for eventual database replay and concurrency testing.
