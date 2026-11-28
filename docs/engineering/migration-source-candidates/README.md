# Forward repair candidates — repository-only staging

These SQL files are **inactive review candidates**, not migrations. They are deliberately outside
`supabase/migrations/` because the repository environment does not currently have a verified
Supabase CLI workflow or disposable PostgreSQL 17 database. Do not copy them into the active
migration directory manually and do not apply them to the hosted project.

## Operational workspace facility isolation

`20261125_operational_workspace_facility_boundary.sql.candidate` is a fail-closed
`pg_get_functiondef` rewrite for the currently observed function body. It changes five exact
fragments:

1. Only `it_admin` and `system_superuser` receive platform-wide bypass classification.
2. Appointment rows require a matching active facility unless a platform administrator has no
   active facility selected.
3. Ward rows with NULL `facility_id` are no longer globally visible.
4. Bed rows with NULL `facility_id` are no longer globally visible.
5. Facility directory results are limited to the active facility for scoped users.

Each source fragment must occur exactly once. Any drift aborts the migration before the function
is replaced. Existing function definition, SECURITY DEFINER declaration, empty search_path,
return type and grants are preserved by CREATE OR REPLACE; the candidate then explicitly
reasserts the authenticated-only RPC grant.

## Billing special-form repair

`20261125_billing_special_form_repair.sql.candidate` changes only the invalid
`pg_catalog.coalesce/greatest/least` qualifications in the existing billing materialization
function. It checks that all three broken spellings exist before replacement and verifies they
are absent afterward. CREATE OR REPLACE preserves the function's signature, return shape,
SECURITY DEFINER declaration, search_path and existing ACL.

## Required promotion gates

Before either candidate is promoted:

- Generate a new timestamped migration with the installed Supabase CLI using
  `supabase migration new`; do not reuse or edit historical migration identities.
- Compare the live `pg_get_functiondef` with the exact candidate anchors on a disposable
  PostgreSQL 17/Supabase environment.
- Run the operational workspace and billing pgTAP contracts, plus the full database suite.
- Verify role-by-role behavior for platform administrators, facility administrators,
  front desk, ward staff and accountants with synthetic fixtures.
- Verify the billing date-window and invoice materialization paths with synthetic data.
- Run migration parity, forward-only checks and a complete clean database replay.
- Review the generated migration and resulting function ACL/search_path before any authorized
  hosted deployment.

The candidate contract in `scripts/forward-repair-candidates-contract.mjs` checks that these
files remain inactive, fail closed on drift, and preserve the intended source-level invariants.
It is not a substitute for PostgreSQL execution or runtime verification.
