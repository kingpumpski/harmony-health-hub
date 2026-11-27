# Canteen patient-order facility isolation — 2026-11-27

## Finding

The historical `get_canteen_active_patient_orders()` RPC authorizes `admin` and `canteen` users, then reads active meal orders by time window. It joins `meal_orders` to `patients` and optionally `meal_plans`, but the query does not constrain those records to the caller's active facility.

The canonical facility-review migration enumerates both `meal_orders` and `meal_plans` as facility-attributed relations. The application also relies on the patient's canonical `facility_id`. A facility-scoped canteen user could therefore receive records outside the active facility through this SECURITY DEFINER RPC.

## Forward-only correction staged

Added `20261127101000_fix_canteen_patient_order_facility_scope.sql`:

- Requires authentication and the canteen/administrator role, or the platform `system_superuser` role.
- Requires a selected active facility for every non-superuser caller.
- Filters meal orders and patients to the same active facility, and filters linked diagnoses and encounters to that facility as well.
- Ensures a linked meal plan belongs to the same facility and the same patient; a mismatched or unresolved linked plan does not leak into the projection.
- Preserves the RPC signature and return shape, fixed search path, authenticated-only execute grant, and PostgREST schema reload.

The historical migration is unchanged.

## Verification boundary

`scripts/canteen-patient-order-facility-repair-contract.mjs` pins the source-level repair and protected-history boundary. This is not PostgreSQL execution evidence. The migration has not been applied to any database; its catalog compatibility and runtime behavior still require a clean PostgreSQL 17 replay and database-level tests.

The global migration identity gate still reports 21 duplicate historical timestamp groups, so the replay cannot start yet. No database was accessed or modified, and no Supabase branch was created.
