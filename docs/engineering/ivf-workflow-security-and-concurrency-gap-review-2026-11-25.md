# IVF workflow security and concurrency gap review

Updated: 2026-11-25

## Scope and evidence

Read-only review of the canonical PostgreSQL definitions for:
- `public.create_fertility_cycle_workflow(uuid,text,text,date,text)`
- `public.transition_fertility_cycle_workflow(uuid,text,text)`
- RLS policies on `fertility_cycles` and `fertility_monitoring`
- `public.assert_patient_facility_context(uuid)`
- Function execute privileges for `anon` and `authenticated`

No SQL was applied and no fertility records were read or modified.

## Confirmed high-priority issue: transition RPC omits facility authorization

The live `transition_fertility_cycle_workflow` is SECURITY DEFINER and executable by authenticated users. It checks that the caller is authenticated and has one of the admin/practitioner/nurse/midwife roles, validates a small set of status strings, then updates the cycle by ID. It does **not**:
- lock and load the cycle before changing it;
- call `assert_patient_facility_context` for the cycle's patient;
- compare the cycle's `facility_id` with the caller's active facility;
- explicitly apply a privileged cross-facility policy;
- validate a transition graph or guard terminal-state re-entry.

The fertility table's restrictive SELECT policies do not repair this boundary: the RPC is SECURITY DEFINER and performs the update with its definer privileges. This is a cross-facility authorization gap in the transition entry point.

### Required forward repair design

When the repository CLI and disposable PostgreSQL 17/Supabase replay environment are available, create a new migration using the installed Supabase CLI workflow. Do not edit historical SQL.

The replacement RPC should:
1. Require `auth.uid()` and an explicit permitted clinical role.
2. Load the cycle with `SELECT ... FOR UPDATE`; fail closed if absent.
3. Resolve patient and cycle facility lineage and reject a cycle whose facility differs from its patient.
4. Call `assert_patient_facility_context(cycle.patient_id)`; for non-privileged staff, require the returned patient facility to equal the active facility. Preserve the special test-user restrictions enforced by the helper.
5. Define any admin/IT-admin/system-superuser exception explicitly and consistently with the application's role policy; do not silently grant cross-facility access to every admin-like role.
6. Enforce a reviewed state-transition graph, including idempotent retries and terminal-state behavior.
7. Audit the old state, new state, actor, patient, cycle, and facility without putting unnecessary sensitive clinical details in audit metadata.
8. Keep a pinned safe search_path, revoke EXECUTE from PUBLIC/anon, and grant only the intended authenticated role.
9. Add SQL regression tests for same-facility success, cross-facility denial, test-account boundary, missing/inactive patient, concurrent transitions, invalid transitions, and unauthorized roles.

## Additional concurrency issue: cycle numbering

The live `create_fertility_cycle_workflow` calls `assert_patient_facility_context` and validates the cycle type, but computes `MAX(cycle_number)+1` for a patient without an advisory lock or another serialization mechanism. Concurrent cycle creation for the same patient can calculate the same next number.

Before changing it, inspect the live unique constraints and indexes. Then serialize on a stable patient-scoped lock or use an equivalent database-enforced allocation strategy, and test two concurrent transactions. Keep the existing facility assertion and audit behavior.

## Existing protections observed

- Both fertility tables have RLS enabled.
- Staff SELECT policies exist; `fertility_cycles` also has restrictive facility-access and facility-identity SELECT guards.
- Both RPCs reject unauthenticated callers.
- Both RPCs are not executable by `anon`; they are executable by `authenticated`.
- Cycle creation already calls `assert_patient_facility_context`, which validates patient status/facility, enforces active facility for ordinary staff, and preserves the dedicated test-facility restriction.

## Broader IVF domain completeness

The current relational foundation is limited to fertility cycles and monitoring. A production IVF service will need separately governed records and permissions for consent/version history, specimen accession and custody, embryology observations, fertilization/culture events, embryo identity and inventory, cryostorage locations and movements, transfer events, outcomes, adverse-event records, and audit trails.

Those are architectural gaps, not permission to encode clinical protocols or automate treatment decisions. Workflow states, required documentation, and clinical decision gates must be approved by qualified fertility clinicians and embryology leadership before implementation. AI or automation must not independently select or authorize treatment.

## Execution boundary

This review is documentation-only. The repository environment has no available local Supabase CLI/PostgreSQL/Docker replay tool, and no disposable database branch has been authorized. Accordingly, no active migration file was hand-created, no canonical DDL was executed, and the issue remains open until a reviewed forward migration passes disposable replay and CI.
