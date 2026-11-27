# Unassigned pharmacy stock access restriction — 2026-11-27

## Security finding

The facility-scoped pharmacy workspace repair already restricts patient, prescription, dispensing-plan, inventory and POS records to the caller's active facility. A separate legacy reconciliation path remained: unassigned inventory has no trustworthy facility attribution, but facility administrators could view the global unassigned-stock queue and assign those records to their selected facility.

Because the source rows have no reliable facility owner, they cannot be safely scoped to an ordinary facility administrator. A facility administrator must not claim an unassigned stock record merely by selecting a facility.

## Forward-only repair

Added `20261127100900_restrict_unassigned_pharmacy_stock_to_platform_superuser.sql`:

- Restricts the unassigned-stock projection in `get_pharmacy_workspace(integer)` to `system_superuser`.
- Restricts `assign_unattributed_pharmacy_inventory(uuid,text)` to `system_superuser` as well.
- Preserves the requirement to select a destination facility and provide a meaningful reconciliation reason.
- Resolves exact function signatures and verifies SECURITY DEFINER plus the existing empty search_path before rewriting.
- Uses exact, count-checked source substitutions and aborts if either expected authorization gate has drifted.
- Preserves function signatures, return types, SECURITY DEFINER mode, empty search_path, and authenticated-only execution grants.

Facility administrators retain facility-scoped pharmacy operations. Global medication catalogue visibility remains shared by design; only inventory rows without verified facility attribution are restricted to the platform superuser reconciliation process.

## Static regression

Added `scripts/migration-pharmacy-unassigned-stock-contract.mjs` and registered it under `npm run test:migration-parity`. The existing pharmacy collision contract was also updated to verify that the earlier forward workspace repair closes the historical patient-linked facility bypass.

## Verification boundary

This is repository-only work. No database was accessed or modified and no migration was applied. Static CI must pass, and clean PostgreSQL replay remains blocked by the 21 duplicate historical migration-version groups. The migration is not considered deployed until replay and catalog/RPC tests pass in an explicitly identified disposable test environment.
