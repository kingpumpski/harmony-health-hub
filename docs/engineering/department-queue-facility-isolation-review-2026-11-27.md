# Department queue facility isolation — 2026-11-27

## Source finding
The latest historical `get_department_queue(text,integer)` definition includes multi-role checks but treats `admin` as a global bypass and has no facility predicate in its result query. The canonical attribution migration adds `facility_id` to `department_queues`, `service_orders`, and `patients`, and the reconciliation trigger derives queue facility from its service order.

## Forward repair
Added `20261127100000_fix_department_queue_facility_scope.sql`:
- Preserves RPC signature, table return contract, queue status filtering, ordering, limit bounds, multi-role checks, and authenticated-only grant.
- Requires active facility for ordinary callers, including facility admins.
- Requires queue, service order, and patient facility IDs all to equal the active facility.
- Reserves cross-facility bypass for `it_admin` and `system_superuser`.
- Does not backfill or expose records with missing facility lineage.

A source contract is wired into migration parity. The existing pgTAP facility-boundary contract has been extended to assert all three facility predicates and the platform-role distinction.

## Validation boundary
This is a source-level repair. The full database replay remains blocked by 21 duplicate historical migration versions; no PostgreSQL replay, database access, database modification, or Supabase branch creation occurred.
