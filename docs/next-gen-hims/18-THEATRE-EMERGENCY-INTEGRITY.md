# Theatre and Emergency Integrity

## Scope

Theatre and emergency workflows use the existing canonical `theatre_cases` and `emergency_cases` tables. No parallel clinical workflow tables are introduced.

## Theatre controls

- Creation is server-authoritative.
- The workflow uses the canonical `scheduled_start` and `theatre_name` columns.
- Linked encounters must belong to the selected patient and remain clinically open.
- Patient/start-time concurrency is serialized with a transaction-scoped advisory lock.
- Active duplicate theatre starts are rejected.
- Lifecycle transitions are explicit and monotonic.
- Terminal completed/cancelled cases cannot be reopened.
- Cancellation/postponement requires a reason.
- Closed linked encounters cannot be progressed through active theatre states.
- Authenticated direct table DML remains revoked; RPC execution is the controlled entrypoint.

## Emergency controls

- Lifecycle transitions are row-locked and server-authoritative.
- Explicit transitions prevent reopening terminal outcomes.
- Terminal outcomes require a documented disposition.
- `disposition_at` is populated atomically for terminal outcomes.
- An assigned clinical officer is retained when the workflow is advanced by an authorized clinician.
- Authenticated direct DML remains outside the workflow boundary.

## Verification

`scripts/test-nextgen-theatre-emergency.mjs` verifies the source-level safety contract. Live migration replay remains a separate deployment prerequisite because the active Harmony Supabase project is not currently connected to the development environment.
