# SECURITY DEFINER Classification Register

Updated: 2026-09-17

## Purpose

This register classifies `SECURITY DEFINER` functions by their intended caller boundary. The Supabase advisor finding count is not treated as a defect count by itself; each function must be evaluated according to whether it is an internal trigger/scheduler helper or a server-authoritative application RPC.

## Classification rules

| Class | Intended caller | Client EXECUTE | Required control |
|---|---|---:|---|
| `INTERNAL_TRIGGER` | PostgreSQL trigger only | No | `EXECUTE` revoked from `PUBLIC`, `anon`, and `authenticated` |
| `INTERNAL_SCHEDULER` | Database scheduler/internal job only | No | `EXECUTE` revoked from `PUBLIC`, `anon`, and `authenticated` |
| `APPLICATION_RPC` | Authenticated application workflow | Yes, where required | Explicit role/facility/ownership validation inside the function |
| `ADMIN_RPC` | Authenticated administrator workflow | Yes, where required | Explicit administrator authorization inside the function |
| `AUTH_HELPER` | Internal authorization composition | No for arbitrary-user probes | Current-user helper exposure only where required by the application |

## Explicit internal-only classifications

The following functions are intentionally outside the Data API execution surface:

- `audit_patient_change()` — `INTERNAL_TRIGGER`
- `validate_service_order_encounter()` — `INTERNAL_TRIGGER`
- `service_order_event_trigger()` — `INTERNAL_TRIGGER`
- `link_invoice_item_service_order()` — `INTERNAL_TRIGGER`
- `generate_patient_code()` — `INTERNAL_TRIGGER`
- `record_system_audit(text,text,text,uuid,text,jsonb)` — `INTERNAL_TRIGGER`
- `notify_due_medications()` — `INTERNAL_SCHEDULER`
- `lock_overdue_medication_slots()` — `INTERNAL_SCHEDULER`
- `has_role(uuid, public.app_role)` — `AUTH_HELPER`
- `is_clinical_staff(uuid)` — `AUTH_HELPER`
- `has_facility_access(uuid, uuid)` — `AUTH_HELPER`
- `can_edit_patient_record(uuid, uuid)` — `AUTH_HELPER`

These boundaries are already represented by dedicated revoke migrations. The contract suite now protects the critical internal-only execute boundary so later function replacement cannot accidentally re-expose an internal helper.

## Intentionally client-callable SECURITY DEFINER workflows

The following are not classified as internal-only merely because Supabase reports them as SECURITY DEFINER. They remain application RPC boundaries and must retain their internal authorization checks:

- `set_facility_routing_mode(text)` — `ADMIN_RPC`
- `recover_stale_report_run(uuid, integer)` — `APPLICATION_RPC` with facility scoping
- Service-order lifecycle RPCs — `APPLICATION_RPC`
- Laboratory workflow RPCs — `APPLICATION_RPC`
- Pharmacy workflow RPCs — `APPLICATION_RPC`
- Insurance claim mutation RPCs — `APPLICATION_RPC`
- Imaging lifecycle RPCs — `APPLICATION_RPC`

## Reconciliation policy

1. Do not revoke a legitimate application RPC solely to reduce the advisor count.
2. Do not expose a trigger/scheduler helper merely because a client workflow currently fails.
3. Every newly introduced SECURITY DEFINER function must be assigned one of the classes above before the readiness gate can be considered complete.
4. Where a function is client-callable, its role/facility/ownership checks must be protected by repository contract tests.
5. The live Supabase advisor count must be interpreted together with this semantic classification rather than used as a standalone pass/fail metric.

## Remaining work

The register is intentionally incremental. The current pass covers the known internal-only boundaries and the highest-risk authenticated workflow boundaries. Remaining SECURITY DEFINER findings require function-by-function review before the final readiness gate is marked complete.
