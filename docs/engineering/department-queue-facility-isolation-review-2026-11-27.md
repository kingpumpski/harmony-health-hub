# Department queue facility-isolation review and forward repair — 2026-11-27

## Evidence reviewed

- `20260930011000_harden_department_queue_role_boundaries.sql`
- `20260930012000_harden_department_queue_multirole.sql`
- `20260930013000_canonical_clinical_facility_attribution.sql`
- `20260930014000_clinical_facility_reconciliation_control_plane.sql`
- `20261013133000_reconcile_operational_workspace_role_resolution.sql`
- `src/pages/DepartmentQueue.tsx`
- Existing pgTAP `facility_boundary_workspace_contract.sql`

## Finding

The latest historical definition of `get_department_queue(text,integer)` correctly replaces first-role-only authorization with independent multi-role checks and department aliases. It nevertheless retains a broad `admin OR it_admin` bypass and its result query has no facility predicate.

The canonical attribution migration adds `facility_id` to `department_queues`, `service_orders`, and `patients`; the reconciliation control plane links queue facility attribution to the parent service order. A forward correction can therefore enforce existing lineage without adding columns or guessing historical facility values.

## Forward repair

The main branch introduced `20261127090000_fix_department_queue_facility_scope.sql`. This PR also retains the later re-versioned `20261127100400_fix_department_queue_facility_scope.sql` repair so the PR's forward-only sequence remains after the current branch/hosted baseline. Both enforce the same facility boundary:

- Preserve the RPC signature, return columns, queue status filter, ordering, limit bounds, and department-role checks.
- Require an active facility for ordinary callers, including facility admins.
- Restrict facility-scoped callers to rows where queue, service order, and patient all match the active facility.
- Reserve cross-facility bypass for `it_admin` and `system_superuser`.
- Keep the empty search_path, SECURITY DEFINER mode, and explicit authenticated-only execution grant.
- Do not backfill null facility lineage or expose unassigned records.

The branch's source regression contract is wired into migration parity and checks the later forward migration. The existing pgTAP facility-boundary contract includes the queue assertions.

## Validation boundary

These are source-reviewed forward repairs. Static contracts can verify SQL source markers; the pgTAP test can validate the installed function when a clean database replay becomes possible. No PostgreSQL replay was run because the 21 duplicate migration-version groups still block preflight. No database was accessed or modified, and no Supabase branch was created.
