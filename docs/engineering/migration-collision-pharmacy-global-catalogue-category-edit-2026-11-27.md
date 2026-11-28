# Pharmacy migration collision dependency review — 2026-11-27

## Scope

This review covers the two migration files touched by the same Git commit `bf0f0cb9`:

- `20261002130000_pharmacy_global_catalogue_facility_stock_and_safety.sql`
- `20261002132500_pharmacy_global_category_edit.sql`

The shared commit means Git ancestry cannot establish a relative order between these two files. The timestamp prefixes do, however, place the catalogue migration before the category-edit migration in a normal version-sorted sequence. That apparent order is now pinned to explicit source dependencies rather than inferred from Git history alone.

## Findings

1. The catalogue migration adds `catalogue_id`, `facility_id`, `barcode`, `nhis_patient_price`, and `nhis_claim_amount` to `public.pharmacy_inventory`.
2. The later category-edit migration defines `update_pharmacy_inventory_item`, which reads `r.catalogue_id` and writes `barcode`, `nhis_patient_price`, and `nhis_claim_amount`. Its function body therefore depends on the earlier catalogue schema extension.
3. Both files define `assign_unattributed_pharmacy_inventory(uuid,text)` and `update_pharmacy_inventory_item(...)`. Their normalized complete function definitions are identical in the current repository. The duplicated definitions do not currently encode competing behavior.
4. The category-edit migration removes legacy overloads before creating the current update RPC. This is a meaningful destructive DDL step and must be validated against the authoritative deployed signature/ACL inventory during replay; this source review does not establish which overloads exist in every environment.
5. The subsequent forward-only repair `20261127100900_restrict_unassigned_pharmacy_stock_to_platform_superuser.sql` tightens the duplicated legacy-stock assignment authorization. The historical source files remain untouched.

## Guard added

Added `scripts/migration-pharmacy-collision-dependency-contract.mjs` to `npm run test:migration-parity`. It checks:

- The two duplicated RPC definitions remain identical after whitespace normalization.
- The earlier catalogue migration explicitly adds all five columns.
- The later category-edit migration still consumes the relevant row field and columns.
- The catalogue migration's version sorts before the category-edit migration.

This guard detects source drift. It does not claim that Git can order the two files, that all hosted databases have the same overload inventory, or that the full migration chain can replay cleanly.

## Remaining verification

- The 21 duplicate historical migration timestamp groups still block migration identity preflight.
- No PostgreSQL startup or clean replay has been completed.
- The historical overload drops need disposable-PostgreSQL replay and catalog/ACL comparison before any production adoption.
- No database was accessed or modified, no migration was applied, and no Supabase branch was created.

## Disposition

The source-level dependency between the two version groups is now explicit and regression-guarded. The same-commit ordering ambiguity is not silently relabelled as resolved. Keep PR #444 draft until duplicate identity reconciliation, clean PostgreSQL replay, database contract tests, and merge-gate verification are complete.
