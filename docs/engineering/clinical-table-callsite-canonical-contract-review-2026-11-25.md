# Clinical table call-site and canonical contract review — 2026-11-25

## Scope and evidence

This review follows the five-table collision documented in [the canonical catalog comparison](./canonical-catalog-collision-20260912024500-comparison-2026-11-24.md).

Evidence sources:
- Application files on `chore/forward-only-migration-governance`: `src/pages/EmergencyBoard.tsx`, `NursingHandover.tsx`, `TheatreBoard.tsx`, `TransfusionBoard.tsx`, and `ClinicalOperations.tsx`.
- Migration sources `20260912024500_global_hims_inpatient_emergency_theatre_insurance.sql`, `20260912036000_global_hims_nursing_care_plan_security.sql`, `20260914140000_theatre_emergency_transfusion_lifecycle_hardening.sql`, and `20260923143000_emergency_theatre_transfusion_patient_context.sql`.
- Read-only canonical catalog queries on project `ygqoptvezotdqhtimdkr`: function bodies, indexes, policies, triggers, table grants, and RLS flags.
- No database writes or deployments were performed.

This is a targeted compatibility review, not a complete audit of every source file or every dependency.

## Application call-site findings

| Table | Current application contract | Compatibility observations |
|---|---|---|
| `emergency_cases` | `EmergencyBoard.tsx` reads `arrival_time`, `acuity`, `arrival_mode`, and status. | These fields exist in the canonical hybrid table. The table also retains the alternate `arrival_at` / `triage_priority` contract, with a compatibility-sync trigger. |
| `nursing_care_plans` | `ClinicalOperations.tsx` creates plans through `create_nursing_care_plan`, passing patient, problem, goal, interventions, priority, encounter, and admission IDs. | Canonical RPC writes `facility_id` and `encounter_id`; it permits blank interventions by storing NULL. The live table's nullable interventions and required `created_by` align with that function. |
| `nursing_shift_handovers` | `NursingHandover.tsx` reads/writes `shift_label`, `clinical_summary`, `pending_tasks`, and `safety_concerns` through RPCs. | The first three feature fields exist in the live table. However, the live create RPC also names a column that is absent from the live table; see the confirmed blocker below. |
| `theatre_cases` | `TheatreBoard.tsx` reads `theatre_name`, `scheduled_start`, `urgency`, and `anesthetist_id`; it creates and assigns cases through RPCs. | The live table contains both anesthetist spellings and both schedule columns. The current create RPC writes the American-spelled `anesthetist_id` and `scheduled_start`, matching the current UI. |
| `transfusion_records` | `TransfusionBoard.tsx` reads `blood_product`, `unit_identifier`, `reaction_observed`, and `reaction_notes`; creates and transitions records through RPCs. | The live create RPC writes the product text into `component`, while the UI reads `blood_product`. A compatibility trigger exists, but its exact mapping must be asserted in an isolated test before changing either side. The live RPC requires a nonblank unit identifier and confirmed consent. |

## Confirmed runtime incompatibility: nursing handover creation

The current canonical function `public.create_nursing_shift_handover` executes an INSERT naming:

- `patient_id`
- `facility_id`
- `ward_id`
- `outgoing_officer`
- `shift_label`
- `clinical_summary`
- `pending_tasks`
- `safety_concerns`
- `escalation_required`

The canonical table catalog previously inspected contains no `ward_id` column. The function includes `ward_id` in its INSERT even when the optional `_ward_id` argument is NULL. PostgreSQL resolves the target column names before executing the INSERT, so passing NULL does not avoid the missing-column error.

The current `NursingHandover.tsx` call supplies the other handover arguments and does not send `_ward_id`. This does not avoid the incompatibility: the function's INSERT still references the missing column. This is a concrete runtime blocker for creating a handover on the inspected canonical schema.

**Safe disposition:** do not add a `ward_id` column or change the hosted function directly as an ad hoc fix. First establish the intended canonical relationship: either restore a properly constrained ward link with a verified data/backfill plan, or create a forward-only function correction that omits `ward_id` if ward linkage is not part of the intended workflow. Validate the chosen contract on disposable PostgreSQL 17 before any deployment. The original historical migration must remain unchanged.

## Nursing care-plan review contract drift

The historical migration `20260912036000_global_hims_nursing_care_plan_security.sql` contains a review routine that updates `reviewed_at`. The canonical table comparison found no `reviewed_at` column, and the current canonical function inventory for nursing-related functions did not include a care-plan review RPC. The live `create_nursing_care_plan` function does not require `reviewed_at`.

This means the historical review path cannot be treated as a currently supported canonical feature based on the evidence gathered. Do not add `reviewed_at` or reintroduce the old RPC merely to make the historical migration look replayable. First decide whether review workflow is required, then design its current table and RPC contract explicitly.

## Security and catalog inventory

All five canonical tables have RLS enabled; none has FORCE RLS. The inspected policies include role-based clinical policies and additional facility-read guards/isolation policies. Direct table grants to `authenticated` are restricted: the tables are generally SELECT-only for that role, with mutation expected through controlled RPCs. The `anon` role has no useful table privileges in the inspected grant results.

The catalog also contains:
- Facility-scope indexes on all five tables.
- Patient/status or schedule indexes, encounter indexes, and officer/assignment indexes where applicable.
- Audit triggers on all five tables.
- Facility-lineage triggers on all five tables, with additional compatibility-sync triggers on emergency, handover, theatre, and transfusion tables.
- Multiple permissive SELECT policies per table, including separate facility-identity/facility-isolation guards. These must be evaluated as a combined PostgreSQL policy expression; do not assume that adding another permissive policy narrows access.

The complete SQL definitions of every policy, trigger function, and all column-level grants were not exhaustively captured in this targeted pass. No policy, trigger, grant, index, or RLS setting was changed.

## Next engineering actions

1. Reproduce the nursing-handover missing-column failure on a disposable PostgreSQL 17 database using the canonical table/function definitions.
2. Decide and document whether handovers require a ward relationship. If yes, specify FK, facility-scoping, nullability, and backfill rules; if no, prepare a new forward-only RPC correction.
3. Add a database contract test that asserts the handover RPC's INSERT target columns are a subset of the actual table columns and exercises the no-ward path.
4. Add an explicit transfusion compatibility test proving the `component` to `blood_product` projection used by the current UI.
5. Add a theatre contract test for both anesthetist column spellings and schedule fields; do not consolidate them until every RPC, trigger, report, and application consumer is inventoried.
6. Recover missing historical migration sources and replay the complete chain on disposable PostgreSQL 17. Do not promote any colliding migration candidate or apply changes to canonical production until replay and catalog parity pass.

## Safety disposition

Read-only canonical inspection and source review only. No canonical schema, data, grants, policies, functions, triggers, or deployment state was changed. PR #444 remains a draft and must not be merged while the handover incompatibility, historical-source gaps, branch divergence, and CI gates remain unresolved.
