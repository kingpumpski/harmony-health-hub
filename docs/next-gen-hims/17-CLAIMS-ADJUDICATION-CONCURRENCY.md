# Claims adjudication and financial concurrency hardening

## Purpose

The claims domain is now treated as a server-authoritative financial and adjudication workflow. The existing claims RPC contracts are preserved so current UI surfaces continue to use the canonical path.

## Controls

- Claim rows are locked with `FOR UPDATE` before lifecycle or financial mutation.
- Terminal `paid` and `voided` claims cannot be reopened or financially edited.
- Repeating the same terminal transition is explicitly idempotent.
- Non-terminal claim states use an explicit monotonic transition matrix rather than arbitrary status assignment.
- Approval cannot exceed the claimed amount.
- Payment cannot exceed the approved amount.
- Approval requires an adjudicated amount.
- Payment requires a positive paid amount.
- Rejection requires a non-empty rejection reason.
- Claim status changes and financial edits append to the existing `insurance_claim_events` ledger.
- Authenticated clients cannot execute the RPCs anonymously or through the public role.
- Canonical clinical audit convergence continues to include `insurance_claims`.

## Concurrency model

The database row lock serializes competing adjudication/financial mutations for the same claim. A second transaction therefore evaluates the latest committed state instead of applying a stale state transition.

## Promotion boundary

The contract test verifies the migration structure and is included in the Quality workflow. Live migration replay and RLS execution remain subject to availability of the correct active Harmony Supabase project. No unrelated Supabase project is used as a substitute.
