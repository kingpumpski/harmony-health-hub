# Live SECURITY DEFINER exposure inventory — 2026-11-27

## Read-only hosted catalog snapshot

Project `ygqoptvezotdqhtimdkr` currently has 313 SECURITY DEFINER functions in the public schema.

| Check | Result |
|---|---:|
| Total SECURITY DEFINER functions | 313 |
| Authenticated EXECUTE | 279 |
| anon EXECUTE | 0 |
| PUBLIC EXECUTE | 0 |
| Empty search_path | 208 |
| Pinned `pg_catalog, public` search_path | 105 |
| SECURITY DEFINER functions with no pinned search_path | 0 |
| Authenticated/anon CREATE on public schema | No / No |

The 105 non-empty paths comprise 89 entries stored as `search_path=pg_catalog, public` and 16 stored as `search_path="pg_catalog, public"`; both are configured with `pg_catalog` first. No authenticated or anonymous caller can CREATE objects in `public`, so these pinned paths do not permit caller-controlled public-schema shadow objects through ordinary Data API roles.

The 279 authenticated-executable functions are the source of the advisor warning count. That count is not itself a vulnerability count: application RPCs intentionally use SECURITY DEFINER to enforce server-authoritative operations. Blanket revocation would break legitimate workflows. The catalog found no anon or PUBLIC execution exposure.

## Authorization-guard review

277 of the 279 authenticated-executable functions matched the existing generic authorization-marker check. Two are narrow wrappers whose authorization is delegated to another SECURITY DEFINER function:
- `create_lab_test_catalogue_item_with_sample_quantity` delegates creation to `create_lab_test_catalogue_item_with_parameters`, which requires `auth.uid()` and the current user's catalogue-create permission before inserting.
- The four-argument `create_ward_unit` wrapper supplies `current_user_facility_id()` to the five-argument overload, which requires an authenticated actor, admin/IT-admin role, active facility and `has_facility_access`.

Updated `supabase/tests/database/security_definer_auth_contract.sql` to explicitly validate these two delegation paths rather than treating them as missing authorization guards. The test also continues to reject anon/PUBLIC EXECUTE exposure.

## Limits

This is a catalog and boundary inventory, not a proof that every authenticated RPC's business authorization is correct. The 279 client-callable functions still require semantic review by role, facility, ownership, input validation and data exposure. The inventory also does not replace function-by-function classification. No hosted database changes were made.
