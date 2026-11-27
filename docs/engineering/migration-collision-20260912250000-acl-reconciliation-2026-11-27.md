# Migration collision ACL reconciliation: 20260912250000 — 2026-11-27

## Source comparison

Compared the two migrations sharing version `20260912250000`:

- `20260912250000_lab_direct_write_lockdown.sql`
- `20260912250000_reconciliation_finalization.sql`

Git ancestry places the laboratory lockdown before the reconciliation finalization. That order is consistent with the SQL source: the finalization repeats the laboratory direct-write revocations, extends the same protection to additional HIMS clinical tables, and explicitly restores authenticated SELECT access without restoring direct write grants.

## Reconciled ACL behavior

- Both migrations revoke authenticated INSERT/UPDATE/DELETE on `lab_orders` and `lab_results`.
- The laboratory lockdown additionally revokes authenticated UPDATE on `lab_orders` and anon EXECUTE on four laboratory workflow RPCs.
- The finalization migration extends authenticated direct-write revocations to emergency, theatre, transfusion, insurance, nursing, ward/bed, medication-administration and prescription tables.
- The finalization migration explicitly grants authenticated SELECT on the laboratory and HIMS tables; it does not grant direct writes.
- Neither migration changes RLS policy definitions. Effective row visibility remains governed by the pre-existing policies.

## Automated source contract

Added `scripts/migration-20260912250000-acl-contract.mjs` to `npm run test:migration-parity`. It pins the duplicate pair's write revocations, explicit read grants, anon RPC revocations, and absence of policy changes or write-grant restoration.

## Remaining limitations

This closes the identified source-level ACL ambiguity for this pair; it does not resolve the duplicate migration version itself. It also does not prove actual deployed ACL state, table grants inherited through other roles, owner privileges, RLS behavior, or RPC execution. Those require PostgreSQL replay and catalog tests after the duplicate identity gate is resolved. Historical migration files remain unchanged; no database was accessed or modified.
