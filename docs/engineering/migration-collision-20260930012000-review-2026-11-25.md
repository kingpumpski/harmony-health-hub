# Migration collision review: 20260930012000

Updated: 2026-11-25

## Scope

Compared the two same-version migration candidates with the canonical hosted function catalog and the application callsite for the department queue. All database inspection was read-only; no patient or queue rows were queried.

Candidates:
- `20260930012000_harden_department_queue_multirole.sql`
- `20260930012000_harden_high_risk_rpc_execution_boundaries.sql`

## Decision

**Neither candidate is safe to replay unchanged.** The department-queue candidate preserves useful multi-role and department-alias handling but omits facility isolation from a SECURITY DEFINER query that returns patient-identifying information. The RPC-hardening candidate contains a function-signature mismatch and would weaken the current empty search_path configuration on several functions.

## 1. Department queue: facility boundary missing

The candidate replaces `public.get_department_queue(text,integer)` with a SECURITY DEFINER function that:
- Requires authentication.
- Checks admin/IT-admin or a role and profile-department match for the requested operational department.
- Normalizes department aliases.
- Returns queue details, service name/amount/status, patient ID, patient names, and patient code.

The live canonical definition has the same key authorization shape and the same gap: its final query joins `department_queues`, `service_orders`, and `patients`, filters only by normalized department and queue status, and does not filter by the active facility or assert patient facility context.

All three tables have nullable `facility_id` columns in the live schema. The `department_queues` and `service_orders` RLS policies include facility-aware SELECT guards, but those policies do not protect this SECURITY DEFINER function's owner-executed query. The RPC is authenticated-executable and anon execution is denied.

The application callsite `src/pages/DepartmentQueue.tsx` invokes the RPC with only `_department` and `_limit`; it does not pass a facility ID. The database function therefore must resolve and enforce the caller's active facility itself.

**Priority forward repair:**
- Fail closed for ordinary staff if no active facility is selected.
- Require queue, service order, and patient facility attribution to be non-null and consistent with the selected facility for ordinary staff.
- Define any global/platform-admin behavior explicitly and separately from ordinary tenant admin access; do not let NULL facility IDs imply global access.
- Preserve the existing role/department alias checks, return columns, ordering, and limit behavior.
- Add tests for Facility A versus Facility B, null active facility, null record facility, mismatched queue/order/patient facility IDs, and approved platform-admin behavior.
- Keep this as a forward-only function replacement; do not rewrite the historical candidate.

## 2. High-risk RPC hardening candidate is stale and replay-unsafe

The candidate alters eight SECURITY DEFINER function search paths from their current configuration to `pg_catalog, public`, then revokes PUBLIC/anon execution and grants authenticated execution.

Read-only canonical catalog inspection found all eight live functions currently use an empty search_path (`search_path=''`), authenticated EXECUTE is true, and anon EXECUTE is false. Replaying the candidate's ALTER statements would therefore weaken the current search-path hardening for these functions. The live definitions also contain evolved facility checks that must not be replaced by older source.

There is also a concrete signature mismatch:
- Candidate references `create_lab_order_with_payment_gate(uuid,text,text,text,text,numeric)` (six arguments).
- The only live overload is `create_lab_order_with_payment_gate(uuid,text,text,text,text,numeric,uuid)` (seven arguments, including `_encounter_id`).

The candidate's ALTER FUNCTION statement for the six-argument identity will fail when replayed against the inspected canonical schema. Do not add a speculative overload to make the historical candidate succeed.

The other reviewed functions currently have explicit authenticated execution and anon denial, with live empty search_path settings. Their bodies include facility checks or active-facility enforcement in the inspected definitions:
- `create_ai_clinical_session`
- `create_imaging_order_with_payment_gate`
- `create_insurance_claim_draft`
- `create_pharmacy_pos_sale`
- `update_patient_workflow`
- `upload_patient_document_metadata`
- `search_patient_directory`

The live laboratory-order RPC also has facility and encounter checks; preserve its seven-argument signature.

## 3. Verification boundaries

- Function identity arguments, SECURITY DEFINER flags, `proconfig`, and anon/authenticated EXECUTE privileges were read from the canonical catalog.
- The department queue page was inspected; it calls the RPC without a facility argument.
- The relevant table facility columns and queue/service-order RLS policies were inspected.
- No queue or patient row contents were queried, and no authenticated user-session exploit test was run.
- No DDL, migration replay, grant change, or deployment occurred.

## Required next work

1. Repair `get_department_queue` through a later forward migration with facility-consistent joins and fail-closed null context.
2. Add database regression tests for the full department queue facility matrix and preserve the existing UI response contract.
3. Do not replay the high-risk RPC candidate; retain empty search_path settings and exact current signatures.
4. Continue collision provenance review and validate any forward repair on disposable PostgreSQL 17/Supabase before canonical deployment.

## Safety disposition

Preserve both candidate files byte-for-byte. Do not rename or delete either duplicate version. No historical SQL has been certified as the exact applied source, and the duplicate timestamp remains unresolved.
