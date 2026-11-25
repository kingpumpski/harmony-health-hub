# Migration collision review: 20260914140000

Updated: 2026-11-25

## Scope and decision

Compared the two candidates sharing version `20260914140000` with the live canonical schema, ACLs, RLS policies, and current RPC definitions:

- `20260914140000_clinical_direct_mutation_surface_hardening.sql`
- `20260914140000_theatre_emergency_transfusion_lifecycle_hardening.sql`

Both feature tracks are reflected in the canonical database. Authenticated direct DML has been revoked on the principal clinical tables. The live workflow RPCs have been substantially hardened beyond the candidate versions.

**Disposition:** preserve both candidates. Do not replay the old function definitions. The current canonical implementations are safer than the candidate bodies and have different signatures/contracts.

## A. Clinical direct-mutation surface

The candidate revokes authenticated DML on lab orders/results, imaging orders, prescriptions, and pharmacy inventory, then adds a pharmacy inventory creation RPC and grants execution to authenticated users.

The canonical database currently confirms authenticated INSERT/UPDATE/DELETE are revoked on all five table families:
- `lab_orders`
- `lab_results`
- `imaging_orders`
- `prescriptions`
- `pharmacy_inventory`

RLS remains enabled. Current workflow RPCs provide the intended write path:
- lab order creation, specimen collection, result entry and approval;
- imaging order creation with payment gating;
- encounter-scoped prescription creation;
- pharmacy inventory creation.

### Candidate function is obsolete

The candidate `create_pharmacy_inventory_item` has an 11-argument signature and older semantics. The live canonical function has a 12-argument signature (adds category), validates active facility, uses facility-scoped inventory, validates expiry/stock rules, resolves a global medication catalogue entry, and writes an audit event. Replaying the candidate could create an overload or reintroduce a weaker inventory path.

### Residual ACL note

The canonical ACL still reports anon INSERT privileges on several of these tables, including lab orders/results and imaging orders, as well as theatre/emergency/transfusion tables. The inspected RLS policies are scoped to authenticated users and no anon policies were present, so this does not by itself prove anonymous writes are possible. It is nevertheless excess privilege exposure; review PUBLIC/default ACL provenance and remove unneeded anon grants in a forward migration after verifying no intended anonymous workflow. The authenticated direct-write boundary is already in place.

## B. Theatre, emergency and transfusion lifecycle

The canonical database has all three table families and has authenticated direct INSERT/UPDATE/DELETE revoked on each.

The current RPC definitions are materially stronger than the candidate versions:

- `create_theatre_case` calls `assert_patient_facility_context`, validates that the encounter belongs to the same patient and facility and is open, validates surgeon/anesthetist roles, and writes facility attribution.
- `transition_theatre_case` locks the case, checks patient/facility context, checks encounter status, enforces a transition graph and requires a reason for cancellation/postponement, then records an audit event.
- `create_emergency_case` validates patient facility, acuity and arrival-mode vocabulary, and assignment permissions.
- `transition_emergency_case` locks the case, checks patient facility lineage, enforces ordered transitions and requires a disposition when closing.
- `create_transfusion_record` validates patient facility, encounter linkage, explicit consent confirmation and unique active unit assignment.
- `record_transfusion_event` locks the record, checks patient/facility lineage, enforces a lifecycle graph and requires independent compatibility verification before the relevant transition, with an audit event.

The candidate function bodies use `SET search_path=public` and omit several of these facility, test-mode, lifecycle and audit controls. Replaying them would be a security and integrity regression.

### Current RLS observations

The three tables have role-based permissive ALL policies plus restrictive facility SELECT guards. Authenticated DML revocation prevents direct PostgREST writes despite the permissive policies. Keep the privilege boundary in place and ensure future migrations do not accidentally re-grant DML.

## Required next actions

1. Preserve the live hardened theatre, emergency, transfusion and pharmacy RPCs; do not restore candidate definitions.
2. Add an ACL contract asserting authenticated direct DML remains denied for all five pharmacy/diagnostic tables and the three theatre/emergency/transfusion tables.
3. Review anon/PUBLIC grants and default privileges; explicitly revoke unnecessary anon DML on exposed clinical tables where no anonymous use case exists.
4. Keep RPC execute grants narrow and verify every SECURITY DEFINER function requires auth, an appropriate role, facility context, safe search_path and audit coverage.
5. Confirm pharmacy inventory UI uses the current 12-argument function contract, not the obsolete candidate overload.
6. Keep clean-bootstrap and hosted-upgrade tests separate; candidate ordering and provenance still need reconciliation against the remote ledger.

## Execution boundary

All inspection was read-only. No clinical row contents were queried. No SQL, privileges, policies, functions, triggers, or migration ledger entries were changed. No migration was renamed, replayed, applied, or deleted. The collision remains unresolved.
