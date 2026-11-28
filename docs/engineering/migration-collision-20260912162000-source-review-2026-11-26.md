# Source interaction review: duplicate migration version 20260912162000 — 2026-11-26

## Scope

This review examines the two active SQL files sharing version `20260912162000` after Git commit ancestry showed their latest path commits diverged:

- `20260912162000_clinical_change_audit_hardening.sql`
- `20260912162000_hims_workflow_completion.sql`

The full current SQL bodies were read from branch `chore/forward-only-migration-governance`. This is static source inspection only; no PostgreSQL parser, clean replay, or live catalog comparison was run.

## Object inventory

### Clinical audit hardening candidate

- Replaces `public.audit_clinical_record_change()`.
- Creates/replaces AFTER INSERT/UPDATE/DELETE triggers on existing tables when present: `encounters`, `diagnoses`, `prescriptions`, `triage_assessments`, `lab_test_catalogue`, and `insurance_claims`.
- Calls the pre-existing `public.record_system_audit(...)` function.
- Revokes direct EXECUTE from PUBLIC and authenticated on `audit_clinical_record_change()`.

### HIMS workflow completion candidate

- Adds `specialist_nurse` to `public.app_role` if absent.
- Creates/extends: `facility_settings`, `lab_test_catalog`, `lab_test_parameters`, `service_orders`, `inpatient_reviews`, and `patient_audit`.
- Creates/replaces: `validate_service_order_transition()`, `audit_patient_changes()`, and `touch_hims_updated_at()`.
- Adds triggers to `service_orders`, `patients`, `facility_settings`, `lab_test_catalog`, and `lab_test_parameters`.
- Enables RLS and creates policies on the six tables listed above.

## Interaction assessment

No same-named table or function definition was found between these two files in the inspected SQL bodies. The first migration modifies `audit_clinical_record_change()` and attaches triggers to six existing clinical tables. The second defines a separate set of tables and functions. This reduces evidence of a direct same-object collision, but does not prove order independence.

The following prerequisites and cross-cutting effects still need explicit validation:

1. The audit migration assumes `public.record_system_audit(...)` exists with a compatible signature and expected audit semantics.
2. The workflow migration assumes `public.app_role`, `patients`, `encounters`, `admissions`, `auth.users`, `public.has_role(...)`, and `public.is_clinical_staff(...)` already exist with compatible signatures.
3. Both migrations rely on `auth.uid()`; their authorization behavior must be tested under authenticated, service, and trigger execution contexts.
4. The audit migration attaches triggers conditionally based on table existence. Its final trigger coverage therefore depends on which prerequisite tables exist at that point in the chain.
5. The workflow migration creates RLS policies over operational and patient-audit data. Its policies and trigger behavior must be compared with later facility-scope hardening migrations and the canonical live catalog.

## Security review flags in the workflow candidate

These are source-level flags for follow-up, not proof of current live exposure:

- `validate_service_order_transition()`, `audit_patient_changes()`, and `touch_hims_updated_at()` are SECURITY DEFINER functions with `SET search_path = public`. A later hardening step should pin a safe search path and verify owner/EXECUTE ACLs against actual call paths.
- Several policies use broad role predicates such as `is_clinical_staff(auth.uid())` or `has_role(auth.uid(), 'admin')` without an explicit facility predicate in this file. Verify whether subsequent migrations add facility scoping and compare against the canonical catalog before treating these as acceptable.
- `patient_audit` stores full OLD/NEW patient row JSONB. Its read policy and any application projection must be reviewed for minimum-necessary disclosure and facility isolation.
- The service-order UPDATE policy allows clinical staff, accountants, and admins; the trigger enforces selected state transitions but does not itself establish facility ownership. Validate the complete RLS/RPC path.

## Disposition

The commit graph remains divergent, so Git ancestry does not supply a migration order. Static source review finds no direct same-object definition collision between these two files, but the prerequisite dependencies, conditional trigger coverage, RLS/facility scope, and SECURITY DEFINER hardening still need replay and catalog verification.

Do not rename either file or select an execution order solely from this review. Preserve both original SQL files. Resolve the shared duplicate version only after prerequisite and dependency analysis plus a disposable PostgreSQL 17 replay. No hosted database was queried or modified for this review.
