# Pharmacy migration collision and facility-scope review — 2026-11-26

## Scope

Reviewed these five active migrations:

- `20261002130000_pharmacy_global_catalogue_facility_stock_and_safety.sql`
- `20261002130000_scope_appointment_workflows_to_active_facility.sql`
- `20261002132000_pharmacy_legacy_stock_reconciliation_rpc.sql`
- `20261002132500_patient_hub_read_rpc_get_compatibility.sql`
- `20261002132500_pharmacy_global_category_edit.sql`

This is source-level evidence only. It does not establish the deployed function definitions, effective grants, or replay order in any database.

## Findings

### 1. Same-version 20261002130000 pair

The pharmacy catalogue migration and appointment facility-scope migration define disjoint function sets and do not create the same tables. The first creates `medication_catalogue` and extends pharmacy inventory/prescription/dispensing-plan structures; the second replaces appointment worklist, schedulable-patient, and appointment-creation RPCs.

Their shared timestamp is therefore not evidence of a direct same-object DDL collision. Their prerequisites still need a clean replay check: pharmacy SQL assumes the existing inventory, prescriptions, dispensing plans, role helpers, audit helper, and service-order relations; appointment SQL assumes the patient/facility assertion and role helpers. Git chronology alone is not a substitute for validating these prerequisites.

### 2. Pharmacy workspace has an admin facility-bypass defect

In `get_pharmacy_workspace(integer)`, the migration computes `v_admin := public.has_role(v_uid, 'admin')`. It then uses `v_admin OR facility_id = v_facility` in the patient and prescription subqueries, and `v_admin OR facility_id = v_facility` in the dispensing-plan subquery.

The project’s authorization model treats `admin` as facility-scoped; platform-wide access is reserved for `it_admin` / `system_superuser` where explicitly permitted. These predicates therefore allow a facility-scoped admin to receive cross-facility patient, prescription, and dispensing-plan data from this SECURITY DEFINER workspace RPC. This is a concrete tenant-isolation risk, not just a migration-order concern.

The POS-sales subquery is filtered by `s.facility_id = v_facility`; the unassigned-inventory branch separately allows `v_admin OR v_superuser`. The latter should be reviewed against the intended authority for legacy stock reconciliation and should not be conflated with ordinary facility administration.

**Required forward repair:** use the active facility predicate for ordinary `admin` as well as clinical/front-desk roles. Only grant cross-facility access through a separately explicit and tested platform role (for example, `system_superuser` or `it_admin` if the policy requires it). Review all returned subqueries, not only the patient list. Preserve the existing RPC signature and JSON contract. Add regression cases proving an admin in facility A cannot receive facility B patients, prescriptions, or dispensing plans, while authorized platform roles retain only their intended access.

No historical migration was edited in this step, and no repair migration was authored before validating the complete live/canonical function contract and existing policies.

### 3. Duplicate function definition is byte-equivalent after whitespace normalization

`assign_unattributed_pharmacy_inventory(uuid,text)` is defined in all three pharmacy migrations at 20261002130000, 20261002132000, and 20261002132500. The three complete function statements are identical after whitespace normalization, including SECURITY DEFINER, empty search_path, role check, active-facility requirement, audit event, and unique-violation handling.

This is a redundant replacement, not a semantic function-body conflict in the checked source. The later category-edit migration also adds `update_pharmacy_inventory_item(...)`; it does not replace the legacy-stock function with a different implementation.

### 4. The 20261002132500 pair is separate in object scope

The Patient Hub migration alters volatility on six existing read RPCs to STABLE. The pharmacy category-edit migration replaces the legacy stock assignment RPC and creates the inventory-update RPC. No same-named function is altered/created by both files in the inspected source. Their shared timestamp alone does not demonstrate a direct object-name conflict.

The Patient Hub ALTER statements require all six target signatures to exist at that point in replay; this remains a prerequisite to verify in clean replay.

## Disposition

- Keep all five historical SQL files unchanged.
- Do not rename, delete, combine, or reorder historical migrations based solely on filename or commit chronology.
- Treat the pharmacy workspace admin bypass as an open security blocker requiring a forward-only correction and facility-isolation tests.
- Treat duplicate function replacement as source redundancy; preserve it until historical provenance and replay sequence are reconciled.
- The migration inventory gate still reports 21 duplicate version groups. No PostgreSQL startup or clean replay was run.
- No database was accessed or modified, and no Supabase branch was created.
