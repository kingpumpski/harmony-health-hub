# Function Execute Privilege Contract

## Purpose

The repository maintains an explicit privilege manifest for selected high-risk application RPCs. The manifest records the intended Data API execution role and requires migration history to contain the corresponding explicit privilege boundary.

## Contract

For each selected RPC signature:

- `authenticated` is the only allowed application EXECUTE role.
- `PUBLIC` EXECUTE must be explicitly revoked.
- `anon` EXECUTE must be explicitly revoked.
- The contract does not replace function-body authorization checks.
- The contract does not assume that every authenticated RPC should have the same role boundary.

## Why this is separate from default privilege hardening

The secure-default migration prevents newly created public functions owned by `postgres` from inheriting EXECUTE from `PUBLIC`, `anon`, or `authenticated`.

The privilege manifest addresses the complementary problem: existing application RPCs need an explicit, reviewable grant contract. This makes intended exposure machine-checkable rather than relying on PostgreSQL defaults or implicit privilege inheritance.

## Current scope

The initial manifest covers selected high-risk patient/workflow RPCs:

- imaging order creation
- insurance claim draft creation
- pharmacy POS sale creation
- appointment workflow creation overloads
- laboratory order creation
- patient workflow updates
- patient directory search

The scope is intentionally incremental. It must not be interpreted as evidence that unlisted RPCs are safe or unsafe.

## Validation

Run `npm run test:function-privilege`.

The full repository test chain also runs this contract.

## Production policy

This contract is source-level and does not itself modify production privileges. Any production privilege change must be represented by an audited migration and verified against the live PostgreSQL catalog.
