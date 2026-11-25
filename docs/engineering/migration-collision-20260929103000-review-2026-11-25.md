# Migration collision review: 20260929103000

Updated: 2026-11-25

## Scope and decision

Reviewed both candidates sharing version `20260929103000` against the live operational workspace function, service tariff schema, RLS policies and function privileges:

- `20260929103000_harden_operational_workspace_search_path.sql`
- `20260929103000_service_catalogue_department_control.sql`

The service catalogue update RPC and its permission boundary are present in the canonical database. The operational workspace function is already more hardened in search-path configuration than the candidate, but its current appointment branch contains a facility-context logic defect.

**Disposition:** preserve both candidates. Do not apply the search-path candidate because it would weaken the live function's empty search path. The service catalogue candidate's function/privilege state is already present. Prioritize a separate forward repair for the workspace facility filter.

## A. Operational workspace search-path candidate

The live `get_operational_workspace(text,integer)` is SECURITY DEFINER and uses `SET search_path TO ''`, which is stronger and more deterministic than the candidate's proposed `pg_catalog, public`. Do not reapply the candidate's ALTER FUNCTION because it would replace the empty search path with a path that includes the exposed public schema.

### High-priority live facility-scope defect

The current appointment module branch filters patients using:

`(v_role IN ('admin','it_admin','system_superuser') OR v_facility IS NULL OR p.facility_id = v_facility)`

For ordinary non-platform staff, if `current_user_facility_id()` returns NULL, the middle OR condition is true and the function returns appointment rows across facilities (subject to its department condition). The function is SECURITY DEFINER, so table RLS does not independently constrain this branch.

This is a static authorization defect in the inspected function body. It must be repaired separately from the search-path migration:
- Require a non-null active facility for ordinary staff before querying facility-scoped modules.
- For ordinary staff, require both appointment and patient facility IDs to equal the active facility.
- Keep explicit privileged-role behavior and test-mode isolation consistent with the shared facility helpers.
- Apply the same fail-closed rule to every module branch; do not rely on facility_id = NULL predicates to imply a denial without verifying each branch.
- Add regression tests for ordinary staff with no active facility, same-facility access, cross-facility denial, privileged selected-facility access, and test-user isolation.

The current workspace function's other module branches use different boolean expressions. Review each branch individually; do not mechanically replace every expression with one generic predicate without understanding platform-admin selected-facility semantics.

## B. Service catalogue department control

The canonical `service_tariffs` table exists with service code/name, department, unit, amount, currency, active state, effective dates and package metadata. It has authenticated SELECT RLS and nine rows at inspection time.

The live `update_service_catalogue_item(uuid,text,text,text,text,numeric,text,boolean)` matches the candidate's contract:
- SECURITY DEFINER with `pg_catalog, public` search path;
- authenticated caller required;
- non-admin callers need `create_services` permission;
- non-admin callers can modify only services in their own department and cannot move the service to another department;
- updates are row-locked and audited;
- PUBLIC/anon EXECUTE is revoked and authenticated EXECUTE is granted.

The live `create_service_catalogue_item` also exists with a pinned search path.

### Residual table ACL note

Authenticated users have table-level INSERT/UPDATE/DELETE privileges on `service_tariffs`, but the only inspected RLS policy is SELECT with `USING true`; there are no authenticated INSERT/UPDATE/DELETE policies. Anon also has table-level SELECT privilege but no anon policy was present. Thus the current RLS policy set blocks direct mutation and anonymous reads, while the server RPC remains the intended mutation path.

These unused table-level grants are unnecessary exposure. After confirming all service catalogue UI writes use the RPCs, consider revoking direct authenticated DML and anon/PUBLIC table access while preserving authenticated SELECT and narrow RPC execution.

## Required next actions

1. Forward-repair `get_operational_workspace` appointment branch to fail closed when ordinary staff lack active facility context.
2. Review all module branches for equivalent NULL-context OR-condition mistakes and selected-facility privilege semantics.
3. Add static and SQL regression coverage for no-active-facility and cross-facility denial on each module.
4. Preserve the live empty search path on `get_operational_workspace`; do not apply the candidate's weaker `pg_catalog, public` setting.
5. Preserve department-scoped service catalogue RPC checks and audit behavior.
6. Migrate any remaining direct service-tariff writes to the RPC and then revoke unnecessary direct DML/anon grants.
7. Reconcile migration provenance and hosted ledger identity before resolving the duplicate timestamp.
8. Validate clean bootstrap and hosted-upgrade paths separately on disposable PostgreSQL 17/Supabase.

## Execution boundary

All inspection was read-only. No appointment, patient, service tariff, or other operational row content was queried; only schema, function definition, policy, privilege and aggregate row-count metadata were inspected. No SQL, ACL, policy, function, trigger, or migration ledger entry was changed. No historical migration was renamed, replayed, applied, or deleted. The collision remains unresolved.
