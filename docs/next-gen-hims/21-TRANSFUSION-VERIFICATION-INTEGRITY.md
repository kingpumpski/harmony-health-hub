# Transfusion Independent Verification Integrity

## Scope

The transfusion workflow now separates record creation from administration verification. Existing `transfusion_records`, lifecycle RPCs, audit infrastructure, and direct-write lockdowns are reused; no duplicate transfusion service is introduced.

## Server-side controls

- A transfusion record may be created in `issued` state after documented consent is confirmed.
- Before `running`, `completed`, or `stopped`, compatibility must be explicitly verified.
- Before administration, an independent clinical witness must be recorded.
- The administering actor cannot self-witness.
- The witness must hold an authorized clinical role.
- Verification locks the transfusion row with `FOR UPDATE` and records an audit event.
- Existing consent, unit-identifier, reaction-documentation, encounter-closure, monotonic lifecycle, idempotency, and audit controls remain enforced.
- Direct authenticated DML remains revoked.

## UI continuity

`TransfusionBoard` now exposes an explicit verification action for issued records and surfaces verification state. Attempting to start an unverified transfusion is rejected by the database trigger rather than relying on client behavior.

## Verification

`npm run test:nextgen-transfusion-safety` checks both the existing lifecycle contract and the independent verification boundary. Live execution remains dependent on access to the correct active Harmony Supabase project.
