# Admission workspace facility isolation — 2026-11-27

## Finding

The historical `get_admission_workspace(integer)` RPC admitted administrators and clinical roles, but its row predicate allowed a broad administrator bypass, a missing active-facility bypass, and rows with NULL bed facility attribution. It joined admissions to patients and optionally beds/wards without requiring the admission and patient to belong to the same selected facility.

## Forward-only correction staged

Added `20261127101100_fix_admission_workspace_facility_scope.sql`:

- Preserves the RPC signature and JSON response shape.
- Requires authentication and the existing clinical admission roles; explicitly permits the platform `system_superuser`.
- Requires an active facility for all non-superuser callers.
- Requires both admission and patient facility IDs to match the selected facility.
- Excludes linked bed/ward records with missing or mismatched facility attribution.
- Limits cross-facility access to `system_superuser`.
- Preserves a fixed search path and authenticated-only EXECUTE grant.

Historical SQL remains unchanged.

## Verification boundary

`scripts/admission-workspace-facility-repair-contract.mjs` pins the intended source contract and historical immutability. PostgreSQL execution and catalog compatibility remain unverified until a clean PostgreSQL 17 replay is possible. The 21 duplicate historical migration versions still block the replay preflight. No database was accessed or modified, and no Supabase branch was created.
