# Migration collision interaction and dependency review — 2026-11-24

This addendum extends the archive fingerprint inventory. It examines whether colliding candidates overlap on database objects or explicitly depend on objects created by another candidate. It is a static source review of the uploaded ZIP, not a replay or a claim about what ran in any hosted environment.

## High-confidence interaction findings

### 1. Version `20260912024500`: shared table definitions

The two candidates both declare and alter the following tables:

- `emergency_cases`
- `nursing_care_plans`
- `nursing_shift_handovers`
- `theatre_cases`
- `transfusion_records`

Both use `CREATE TABLE IF NOT EXISTS`, so replaying both does not guarantee the second file's intended table shape is installed: an existing table is not reconciled to the other candidate's definition merely by the `IF NOT EXISTS` clause. The candidates also create different indexes, policies, triggers, and functions around overlapping operational areas. This is the strongest schema-overlap collision in the 21-group set. The candidates must be compared column-by-column, constraint-by-constraint, and policy/trigger-by-policy/trigger against the authoritative live catalog and original source provenance before any version decision.

### 2. Version `20260912250000`: overlapping laboratory privilege changes

Both candidates revoke authenticated direct write privileges from `lab_orders` and `lab_results`. One is laboratory-specific; the other is a broader cross-module finalization script that includes the same lab revocations plus other clinical tables. This suggests a potential subset/superset relationship, but does not prove equivalence: the full grant/revoke matrix, ordering, and expected application scope must be compared. Applying both under distinct new versions may be redundant; choosing one may omit intended non-lab restrictions.

### 3. Version `20260929200000`: three distinct migrations with a later dependency

The three colliding files cover:
- canteen menu/realtime RLS policy replacement;
- the `get_role_dashboard_summary()` implementation;
- secure default EXECUTE privileges for functions created by selected owner roles.

These are not interchangeable. A later candidate at `20260929203000_active_dashboard_role_context.sql` reads the live definition of `public.get_role_dashboard_summary()` via `pg_get_functiondef`, rewrites its signature and role-selection block, and creates `get_role_dashboard_summary_for_role(text)`. That later migration therefore depends on the dashboard-summary function having been created with the expected body. The candidate at `20260929200000_role_dashboard_kpi_cleanup.sql` is a directly relevant source dependency. The default-privilege migration also has temporal significance: its effect applies to subsequently created functions by the named owner roles, so moving it across later function-creation migrations can change effective grants.

### 4. Version `20260929203000`: active dashboard role context vs search-path hardening

One candidate dynamically derives a role-specific dashboard function from the earlier dashboard summary function. The other applies `ALTER FUNCTION ... SET search_path` to a list of workspace RPC signatures. They have distinct purposes, but both rely on the exact function catalog present at that point in the chain. The search-path script is not a substitute for the dashboard-context migration.

### 5. Version `20260930012000`: queue authorization vs RPC execution hardening

One candidate replaces `get_department_queue(text, integer)` with multi-role and department-alias authorization logic. The other hardens search paths and EXECUTE privileges for a selected set of patient-scoped SECURITY DEFINER RPCs. They do not define the same function set and cannot be treated as alternatives.

### 6. Version `20261002130000`: pharmacy catalogue and appointment workflow scope

One candidate introduces a global medication catalogue and modifies pharmacy inventory/prescription structures and related RPCs. The other scopes appointment worklist and appointment workflow RPCs to the active facility. The feature domains differ. Both candidates may be required by the product history, but their shared timestamp cannot be resolved by selecting the larger file or later-looking filename.

## Broader archive-level note: repeated function names are versioned evolution

The archive contains many repeated `CREATE OR REPLACE FUNCTION` definitions across different timestamps. Examples include `create_appointment_workflow`, `get_operational_workspace`, `create_encounter_prescription`, `get_laboratory_workspace`, and pharmacy lifecycle RPCs. This is consistent with iterative migration-based function evolution and is not, by itself, evidence of a defect. It does mean that restoring a fresh environment requires the complete ordered migration history: copying only the first definition or only the latest definition can omit intermediate table, type, grant, or helper-function prerequisites.

## Safe disposition

- Keep every colliding source candidate archived and fingerprinted.
- Do not bulk rename or delete any candidate.
- Do not combine SQL files merely because one appears to be a superset.
- For shared table definitions, compare full DDL and live catalog state.
- For dynamic function-body transformations, preserve and validate the exact prerequisite function definition.
- For default privileges and explicit grants, reconstruct owner-role and creation-time ordering.
- Use separate, later, explicitly documented migration versions only after provenance, dependency ordering, and isolated replay are established.
- Keep canonical hosted history and fresh-environment bootstrap as separate tracks.

No SQL was modified or applied by this review. No Supabase project was changed.
