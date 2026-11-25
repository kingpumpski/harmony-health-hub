# Migration collision review: 20261002130000

Updated: 2026-11-25

## Scope and decision

Reviewed both migration candidates sharing version `20261002130000`:

- `20261002130000_pharmacy_global_catalogue_facility_stock_and_safety.sql`
- `20261002130000_scope_appointment_workflows_to_active_facility.sql`

Read-only comparison against the canonical hosted catalog found the exact version absent from `supabase_migrations.schema_migrations`, while the principal appointment RPC definitions and pharmacy catalogue/workspace objects exist live. The live pharmacy function bodies are not uniformly identical to the pharmacy candidate.

**Disposition:** preserve both original files. Do not rename, delete, replay, or mark either candidate applied. The hosted schema demonstrates that substantial behavior is present, but does not establish which migration source created it or whether every statement in either candidate ran.

## A. Appointment active-facility workflow

The live catalog contains all four appointment functions defined by the candidate:

- `get_appointment_worklist(integer)`
- `get_appointment_schedulable_patients(integer)`
- `create_appointment_workflow(uuid,timestamptz,text,text,text,uuid)`
- `create_appointment_workflow(uuid,timestamptz,text,text)`

The inspected live definitions match the candidate's material facility protections:

- Worklist and schedulable-patient reads reject a null active facility.
- Worklist results require both appointment and patient facility IDs to equal the active facility.
- Both creation overloads require an active facility and reject a patient whose facility differs.
- The SECURITY DEFINER functions use an empty search path.

This is strong evidence that the intended appointment behavior is represented in the canonical schema. It is not proof that this exact migration file was applied: the exact version is absent from the hosted ledger, and function bodies can be created or replaced by other migrations or manual SQL.

The candidate does not add clinician schedule-overlap or capacity enforcement. The existing concurrency/scheduling gap remains a separate follow-up and must not be described as solved by this facility-scope migration.

## B. Pharmacy global catalogue and facility-owned stock

The live catalog contains:

- `public.medication_catalogue`
- `public.add_global_medication_to_facility(uuid)`
- `public.create_pharmacy_inventory_item(...,text)`
- `public.get_pharmacy_workspace(integer)`

The inspected live `get_pharmacy_workspace(integer)` body includes the candidate's global catalogue, unassigned-inventory, facility-inventory, prescriptions, dispensing plans and POS projections. The live `add_global_medication_to_facility(uuid)` body also follows the candidate's facility-bound creation path.

However, the live `create_pharmacy_inventory_item(...,text)` definition differs from the candidate. The candidate requires expiry, positive retail price and a configured reorder level before positive stock can be made available; the inspected live definition requires expiry for positive stock but does not include the candidate's price/reorder-level predicate. This is a material source/body divergence, not an exact match. Other statements in the candidate were not all individually proven against live catalog metadata in this review.

The pharmacy workspace candidate has an additional authorization question for follow-up: it treats `admin` as a cross-facility override for patient and prescription projections, while ordinary staff are facility-scoped. Confirm that this is the intended admin model and that it aligns with the application's facility-context contract before changing it. Do not infer that every administrative role should have global patient access.

## C. Ledger and provenance

The canonical ledger query returned no row for version `20261002130000`. The presence of current functions/tables is not enough to assign the hosted ledger identity to either candidate. A different version, a later replacement, or manual SQL may have produced the live state.

Required evidence before classifying the duplicate group:

1. Recover the original deployment/migration source and any alternate hosted version identity for each candidate.
2. Compare full SQL fingerprints, function definitions, table/column/index/constraint/policy state and dependency/callsite evidence.
3. Establish which statements are represented, superseded, missing, or unsafe to replay.
4. Test existing-hosted upgrade and clean-install bootstrap separately on disposable PostgreSQL 17/Supabase.
5. Preserve the two tracks: do not use a current schema dump as a fabricated historical baseline.

## Required next actions

1. Keep both candidates immutable pending provenance recovery.
2. Retain the active-facility appointment contract and add schedule-overlap/capacity concurrency tests in a separate, forward-only change.
3. Reconcile the live pharmacy inventory RPC's price/reorder-level validation with current product requirements and UI behavior; do not blindly restore the older candidate body.
4. Verify pharmacy administrator facility semantics and test cross-facility isolation for each role.
5. Inspect all remaining pharmacy candidate DDL/ACL/policy statements against live metadata before declaring parity.
6. Continue duplicate-version reviews for `20261002132500` and the earlier unresolved groups.
7. Do not mark either candidate as applied or remove the collision until original provenance and both replay tracks are verified.

## Execution boundary

The canonical Supabase inspection was read-only and limited to migration-ledger identity and function definitions. No patient, prescription, inventory or pharmacy transaction row contents were queried. No SQL, ACL, policy, function, trigger, schema object, or migration ledger entry was changed. No historical migration was renamed, replayed, applied, or deleted. No disposable replay was run because a local Supabase CLI/PostgreSQL/Docker environment is not available in this session. The collision remains unresolved.
