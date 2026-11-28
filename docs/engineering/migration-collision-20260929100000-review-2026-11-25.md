# Migration collision review: 20260929100000

Updated: 2026-11-25

## Scope and decision

Reviewed the two candidates sharing version `20260929100000` against canonical ward-table privileges/RLS, insurance-company schema, foreign keys, RPCs and indexes:

- `20260929100000_harden_ward_table_data_api_boundary.sql`
- `20260929100000_insurance_company_master_data.sql`

Both feature tracks are represented in the live database. The ward-table privilege boundary is already substantially present. The insurance-company master schema and RPCs exist and are more hardened than the original candidate in their function search paths. Some unnecessary table-level grants remain, but RLS policies currently block direct mutation.

**Disposition:** preserve both original candidates. Do not replay the schema/function candidate unchanged or assume the old ward table surface is fully retired.

## A. Ward table Data API boundary

Canonical inspection confirms `wards`, `ward_units`, and `ward_beds` all have RLS enabled, authenticated SELECT access, and authenticated direct INSERT/UPDATE/DELETE revoked. Anon has no SELECT privilege on these three tables. This matches the primary intent of the candidate.

The older `beds` table still exists as a separate legacy table. It has RLS enabled and authenticated DML revoked, but anon has table-level SELECT privilege. The inspected `beds` policies are all TO authenticated; no anon policy was present, so this privilege alone does not prove anonymous rows are visible. It is nevertheless a residual excess grant that the candidate does not remove, because it only revokes from `wards`, `ward_units`, and `ward_beds`.

**Disposition:** keep the current DML revocations on the three active ward tables. Determine whether `beds` is still used; if it is not an intentional public surface, revoke anon/PUBLIC access in a separate forward-only correction after callsite and API exposure checks.

## B. Insurance company master data

The canonical database contains `insurance_companies` with the candidate's core columns, unique code/name constraints, active flag, metadata and created-by reference. It also has `insurance_company_id` columns and FKs on patients, insurance cases, insurance claims and insurance service tariffs, plus the corresponding lookup indexes.

The live RPCs exist:
- `list_insurance_companies(boolean)` is SECURITY INVOKER with a pinned `pg_catalog, public` search path. Its SELECT policy permits admin/IT-admin only.
- `create_insurance_company(text,text,text,text,text,text,text)` is SECURITY DEFINER, has an empty search path, checks authenticated admin/IT-admin role, validates required code/name, relies on unique constraints for collision protection, and writes an audit event.
- `update_insurance_company(uuid,text,text,text,text,text,text,text,boolean)` is SECURITY DEFINER, has an empty search path, checks authenticated admin/IT-admin role, validates the target and duplicate code/name, and writes an audit event.

The current RPCs are stronger in search-path hardening than the candidate's explicit `pg_catalog, public` SECURITY DEFINER search path.

### Residual direct-grant observation

The canonical ACL reports authenticated INSERT/UPDATE/DELETE and anon SELECT privileges on `insurance_companies`. However, the only inspected RLS policy is authenticated admin/IT-admin SELECT; there are no INSERT/UPDATE/DELETE policies and no anon policies. Therefore RLS blocks those direct table paths in the current policy set. The SECURITY DEFINER RPCs provide the intended mutation path.

Still, direct DML grants are unnecessary and make future policy mistakes more consequential. Consider revoking authenticated direct DML and anon/PUBLIC table privileges in a separate forward migration, retaining the RPC grants and admin-only SELECT policy. Verify UI calls use the RPCs first.

### Constraint and model notes

The live schema has several overlapping nonnegative/effective-date checks on `insurance_service_tariffs`. They are logically overlapping, not automatically safe to drop; compare validation state, names, dependencies and query behavior before cleanup.

The live insurance claim and insurance case tables have facility attribution and restrictive facility SELECT policies. Keep those boundaries when extending the master directory. The master `insurance_companies` row itself is global reference data and is intentionally admin/IT-admin readable in the inspected policy.

## Required next actions

1. Preserve the existing ward table direct-DML revocations and test anon/authenticated access explicitly.
2. Inventory all references to legacy `public.beds`; if unused, archive it through a separate deprecation plan and revoke its unnecessary anon SELECT grant.
3. Revoke unnecessary direct table DML on `insurance_companies` after confirming all UI writes use the current RPCs; preserve admin-only SELECT and RPC execute.
4. Review insurance company and tariff constraints for true duplicates before cleanup; do not drop constraints based on name similarity alone.
5. Preserve the current empty-search-path SECURITY DEFINER implementations; do not restore candidate function bodies.
6. Add regression tests for admin/IT-admin directory management, non-admin denial, and facility-aware claim/case access.
7. Reconcile the hosted migration ledger and original source provenance before resolving the duplicate version.
8. Validate clean bootstrap and hosted-upgrade paths separately on disposable PostgreSQL 17/Supabase.

## Execution boundary

All inspection was read-only. No patient, insurance, claim, or facility row contents were queried. No SQL, ACL, RLS policy, function, trigger, constraint, index or migration ledger entry was changed. No historical migration was renamed, replayed, applied, or deleted. The collision remains unresolved.
