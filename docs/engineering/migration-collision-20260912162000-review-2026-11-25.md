# Migration collision review: 20260912162000

Updated: 2026-11-25

## Scope and decision

Reviewed the two repository candidates sharing version `20260912162000` against the live canonical schema, functions, triggers, constraints, and RLS policies:

- `20260912162000_clinical_change_audit_hardening.sql`
- `20260912162000_hims_workflow_completion.sql`

**Both feature areas are represented in the live database, but the candidates are historical snapshots and must not be replayed unchanged.** Preserve both originals. No winner is selected and no migration history is altered.

## A. Clinical change audit candidate

The candidate introduces `audit_clinical_record_change()` and attaches additional AFTER INSERT/UPDATE/DELETE triggers to encounters, diagnoses, prescriptions, triage assessments, lab catalogue, and insurance claims.

The live canonical database already has a common `audit_operational_row_change()` trigger on the overlapping core tables (encounters, diagnoses, prescriptions, triage assessments, insurance claims, etc.). It records actor, operation, entity, changed-column names and audit source into `system_audit_log`, with a pinned `pg_catalog, public` search path. The candidate function is not the live trigger function.

Reintroducing the candidate triggers would duplicate audit events for the overlapping tables. The candidate also serializes full OLD/NEW row JSON into audit metadata, which can copy unnecessary sensitive clinical content into a broad audit surface. Its trigger calls `record_system_audit`, which requires a non-null `auth.uid()`; background/service-role writes with no user JWT could fail when the trigger fires. The live operational audit trigger allows a null actor and does not have that failure mode.

**Disposition:** do not add the candidate triggers alongside the current operational audit triggers. Preserve the current changed-column audit approach unless a documented audit requirement calls for a carefully scoped additional event. Any future audit change must be tested for service-role/background writes and data minimization.

## B. HIMS workflow completion candidate

All six major table families exist live:
- `facility_settings`
- `lab_test_catalog`
- `lab_test_parameters`
- `service_orders`
- `inpatient_reviews`
- `patient_audit`

Live row counts at review time: facility settings 1; lab test catalogue 0; parameters 0; service orders 14; inpatient reviews 0; patient audit 11.

The live definitions have materially evolved:
- `facility_settings` now uses a text singleton key and includes payment-routing and emergency override controls; the candidate used a UUID key and different column contract.
- `lab_test_catalog` and `lab_test_parameters` have different column names and nullable/code constraints from the candidate.
- `service_orders` uses the live status contract `pending_payment_approval/released/in_progress/completed/cancelled`, has facility attribution, and patient deletion is RESTRICT. The candidate uses a different payment/fulfillment split and patient CASCADE.
- `inpatient_reviews` includes `facility_id` and facility-aware restrictive policies; the candidate has no facility column.
- `patient_audit` uses `actor_user_id`, `operation`, `changed_fields`, and patient FK ON DELETE RESTRICT. The candidate uses different columns and patient CASCADE.

The live service-order workflow also has evolved triggers: encounter/patient validation, facility attribution, audit, and service-order event recording. Do not replace these with the candidate's earlier `validate_service_order_transition` implementation.

### Specific integrity and security observations

1. **Audit duplication risk:** the candidate clinical audit triggers overlap with the live `audit_operational_row_change` triggers. Installing both would generate duplicate events.
2. **Audit data minimization:** the candidate stores full OLD/NEW records in `system_audit_log`; the live common audit trigger records changed-column names and operation metadata. Avoid copying entire clinical rows unless explicitly required and access-controlled.
3. **Background write reliability:** the candidate trigger calls `record_system_audit`, which rejects a null `auth.uid()`. Service-role and scheduled writes without a user JWT must be tested before adopting any trigger-based audit design.
4. **Patient retention:** the candidate's `patient_audit` FK uses ON DELETE CASCADE, while live patient audit history uses ON DELETE RESTRICT. The live behavior better protects audit history from accidental physical patient deletion; preserve retention semantics pending a formal archive policy.
5. **Facility boundaries:** live `inpatient_reviews` has restrictive facility policies for SELECT/INSERT/UPDATE/DELETE and a facility FK. Candidate role-only policies are insufficient and must not replace them.
6. **Service-order financial/workflow semantics:** candidate `payment_routing_mode` values and `fulfillment_status` state machine differ from the live operational contract. Never merge the state machines by renaming statuses without mapping current rows and all RPC/UI consumers.
7. **Facility settings visibility:** live authenticated users can read the singleton facility settings row. Confirm that no future configuration fields contain secrets or privileged-only data.

## Required next actions

1. Keep the current operational audit triggers; add tests to prevent duplicate audit trigger installation on the same table.
2. Test service-role and background write paths for audit reliability and ensure the audit actor can be null when no user JWT exists.
3. Preserve patient audit ON DELETE RESTRICT and define a patient archive/retention workflow before any change.
4. Maintain current service-order status, facility, patient/encounter, and event contracts. Add concurrency tests for competing status changes and payment-release transitions.
5. Review facility-settings field classification before adding any sensitive configuration.
6. Compare all subsequent migrations and original commit provenance before assigning a unique historical identity to either candidate.
7. Test clean bootstrap and upgrade-from-hosted-baseline on disposable PostgreSQL 17/Supabase.

## Execution boundary

This was a read-only review. No clinical row contents were read; only aggregate counts and catalog metadata were queried. No SQL was applied, no migration file was renamed, and no canonical database object was modified.
