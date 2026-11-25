# Migration collision review: 20260912250000

Updated: 2026-11-25

## Scope and decision

Reviewed both candidates sharing version `20260912250000` against the canonical PostgreSQL grants, RLS policies, workflow RPCs, triggers, and current schema:

- `20260912250000_lab_direct_write_lockdown.sql`
- `20260912250000_reconciliation_finalization.sql`

Both represent a privilege-hardening track. The canonical database already reflects much of the intended restriction, but not all of it. The candidates are not interchangeable historical alternatives: the second is a broader operational lockdown that subsumes the laboratory revocations and adds several inpatient/clinical tables.

**Disposition:** retain both originals and treat the canonical ACL differences as migration-history drift requiring provenance reconciliation. Do not replay either file unchanged or mark the whole group complete based on the lab table grants alone.

## A. Laboratory direct-write lockdown

Canonical inspection confirms:
- Authenticated users have SELECT but no INSERT/UPDATE/DELETE table privileges on `lab_orders` and `lab_results`.
- Both tables have RLS enabled, facility-aware restrictive SELECT policies, and operational audit/facility synchronization triggers.
- `collect_lab_sample`, `enter_lab_result`, `approve_lab_result`, and related lab workflow RPCs are SECURITY DEFINER with pinned empty search paths; inspected RPCs are executable by authenticated users but not anon.
- The current RPC implementations validate role, patient/facility context, and relevant order/result state. Approval locks both result and order and validates patient/order/result facility agreement.

The canonical database therefore has the core authenticated direct-write lockdown described by the first candidate.

### Residual ACL note

The catalog ACL still grants anon INSERT/UPDATE/DELETE on several clinical tables, including `lab_orders`, `lab_results`, and other operational tables. The inspected RLS policies target authenticated users and no anon policies were present for these tables, so the ACL finding alone does not establish that anonymous writes succeed. It is nevertheless unnecessary privilege exposure and should be removed explicitly after confirming no public workflow depends on it. Do not conflate this with the already-revoked authenticated grants.

## B. Broader HIMS reconciliation finalization

Canonical privilege checks show that authenticated INSERT/UPDATE/DELETE are already revoked for most tables listed in the second candidate, including:
- emergency cases;
- theatre cases;
- transfusion records;
- insurance claims;
- medication administrations;
- prescriptions;
- ward units and ward beds;
- laboratory orders and results.

The workflow RPCs inspected for emergency cases, theatre cases, transfusion records, ward-bed placement/transfer, nursing care-plan creation, and nursing handover creation are SECURITY DEFINER, authenticated-only entry points with role and/or patient/facility checks. This is consistent with the candidate's intended server-mediated workflow architecture.

### Confirmed canonical drift: nursing tables

The broad candidate also revokes all authenticated DML on `nursing_care_plans` and `nursing_shift_handovers`. That is **not** the current canonical ACL:

- `nursing_care_plans`: authenticated UPDATE and DELETE remain granted (INSERT is revoked).
- `nursing_shift_handovers`: authenticated INSERT, UPDATE, and DELETE remain granted.

Both tables have permissive role-based ALL policies. They also have restrictive facility SELECT policies, but the inspected policies do not provide an equivalent restrictive facility boundary for direct INSERT/UPDATE/DELETE. The handover table has a facility-lineage trigger; that helps prevent mismatched facility attribution but does not make unrestricted direct mutation equivalent to a reviewed workflow RPC.

The canonical RPCs include `create_nursing_care_plan`, `create_nursing_shift_handover`, and `acknowledge_nursing_handover`. These support a server-mediated model, but before revoking direct DML, inventory all application callsites for care-plan updates/deletes and handover mutations and ensure corresponding audited RPCs exist. Do not assume create/acknowledge RPCs cover all edit/archive workflows.

**This is a real ACL drift from the broad candidate and a high-priority follow-up.** The migration must not be applied until callsites are reconciled and tests prove that all legitimate nursing workflows still function.

### Nursing handover schema dependency

The live `create_nursing_shift_handover` RPC inserts `ward_id`, while the canonical `nursing_shift_handovers` table previously inspected lacked that column. A staged forward migration `20261125090000_restore_nursing_handover_ward_link.sql` proposes adding it but is not applied. Therefore, the create RPC is not yet a verified working replacement for direct INSERT. Do not revoke the remaining direct INSERT path until the ward-link migration has passed disposable replay, been safely applied through the approved process, and the RPC is verified.

## Required next actions

1. Inventory frontend and backend callsites for direct INSERT/UPDATE/DELETE against both nursing tables.
2. Add narrowly scoped, audited RPCs for any legitimate edit/archive operations that currently depend on direct DML; preserve clinical record retention rather than enabling hard deletion by default.
3. Resolve and test the missing `ward_id` schema dependency before removing the current handover INSERT compatibility path.
4. After callsite migration, add a forward-only ACL migration that revokes authenticated DML from both nursing tables, while preserving intended SELECT and trusted server/service-role access.
5. Review and remove unnecessary anon DML grants across exposed clinical tables, after confirming no anon workflow is intended. Retain RLS and do not treat privilege revocation as a substitute for row policies.
6. Add automated ACL contracts that assert both positive (required RPCs executable by authenticated) and negative (direct DML denied; anon denied) cases.
7. Confirm all SECURITY DEFINER RPCs have pinned search paths, explicit auth/role checks, patient/facility checks where applicable, and narrowly scoped EXECUTE grants.
8. Reconcile the two source candidates with the hosted migration ledger and subsequent migrations; do not infer application from current object state alone.
9. Validate clean bootstrap and upgrade-from-hosted-baseline on disposable PostgreSQL 17/Supabase.

## Execution boundary

All inspection was read-only. No clinical row contents were queried. No privileges, policies, functions, triggers, or migration ledger entries were changed. No migration file was renamed, applied, or deleted. The collision remains unresolved.
