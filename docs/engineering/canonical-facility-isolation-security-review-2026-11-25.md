# Canonical facility-isolation security review — 2026-11-25

## Scope and safety boundary

This review continues the collision review of migration versions `20260929103000`, `20260929150000`, and `20260929200000`. It records fresh read-only catalog inspection of the hosted project `harmony-health-hub` (project ref `ygqoptvezotdqhtimdkr`). No SQL was applied, no clinical rows were read, and no migration source was reconstructed or promoted.

The affected functions are SECURITY DEFINER. Their table queries therefore must enforce facility boundaries explicitly; ordinary table RLS cannot be assumed to constrain their results.

## 1. Confirmed live cross-facility exposure paths

### 1.1 Canteen active patient orders

Live signature: `public.get_canteen_active_patient_orders()`.

The function authenticates the caller and requires `admin` or `canteen`, then returns patient identity, meal-order details, meal-plan restrictions, chronic-condition context, and current diagnoses. Its time/status predicates do not scope `meal_orders.facility_id`, `patients.facility_id`, or a linked `meal_plans.facility_id` to the caller's active facility.

All three facility columns exist. Since the function is SECURITY DEFINER, RLS on the underlying tables is not a substitute for those missing predicates.

**Required forward repair**
- Preserve authentication and the existing role allowlist unless a separately reviewed product policy changes it.
- Resolve the caller's active facility using `public.current_user_facility_id()`; fail closed when a canteen user has no active facility.
- Require `meal_orders.facility_id = v_facility` and `patients.facility_id = v_facility`.
- When a meal plan is linked, require `meal_plans.facility_id = v_facility`; do not let a null or mismatched parent silently widen access.
- Keep test-mode users constrained to the configured test facility. Do not let a platform/admin branch bypass test-mode isolation.
- Do not add an all-facility administrator mode to this read RPC without an explicit, audited requirement and regression coverage.

### 1.2 Laboratory workspace

Live signature: `public.get_laboratory_workspace(integer)`.

The function checks authentication, admin/lab-technician role, and the laboratory department. It returns patient directory rows, catalogue rows, lab orders, and results. The live `patients`, `lab_orders`, and `lab_results` tables all have `facility_id`, but the patient, order, and result subqueries currently do not filter by the caller's active facility.

The lab-order result suppression predicate for pending payment approval is not a facility boundary.

**Required forward repair**
- Require a non-null active facility for ordinary laboratory staff.
- Scope the patient directory to `patients.facility_id = v_facility`.
- Scope orders to `lab_orders.facility_id = v_facility` and verify their patient belongs to that same facility.
- Scope results to `lab_results.facility_id = v_facility`; join the parent order and patient and require all three facility IDs to agree. This also prevents a mismatched child row from crossing a facility boundary.
- Preserve the existing role, department, result status, and pending-payment behavior.
- Keep catalogue access global only if the existing product contract confirms that the catalogue is shared master data.

### 1.3 Imaging workspace

Live signature: `public.get_imaging_workspace(integer)`.

The function checks authentication and admin/radiologist/radiology-technician role plus department, but the patient directory and imaging-order query do not filter by active facility. Both `patients` and `imaging_orders` have `facility_id`.

**Required forward repair**
- Require a non-null active facility for ordinary imaging staff.
- Scope the patient directory to the active facility.
- Scope imaging orders to `imaging_orders.facility_id = v_facility` and require the joined patient facility to match.
- Preserve role/department checks, selected fields, ordering, and limit clamping.
- If administrators need cross-facility review, implement a separately explicit selected-facility contract; do not interpret a null facility as permission to see every facility.

### 1.4 Operational workspace appointments

Live signature: `public.get_operational_workspace(text,integer)`.

The appointment branch currently includes:

```sql
(v_role NOT IN ('admin','it_admin','system_superuser') OR v_facility IS NULL OR p.facility_id=v_facility)
```

For a non-platform staff caller with `v_facility IS NULL`, the middle OR term is true. This removes the facility boundary. The branch also lacks an explicit `appointments.facility_id = v_facility` predicate even though the appointments table has that column.

**Required forward repair**
- For non-platform staff, require an active facility and match both appointment and patient facility IDs to it.
- For platform administrators, scope to their selected active facility by default as well. A null active facility must not silently mean global access.
- If a global administrative view is a genuine requirement, expose it as a separate explicit, audited capability with dedicated tests and test-mode isolation.
- Preserve department filters and existing role checks.

## 2. Facility helper semantics observed

Read-only inspection confirmed:

- `current_user_facility_id()` returns an active-facility context where available; system-superuser context is derived from `user_active_facilities`; test users resolve to the configured test facility.
- `assert_patient_facility_context(uuid)` rejects missing/inactive patients and unresolved patient facility attribution. It evaluates test mode before administrator cross-facility privileges and constrains test users to the test facility. For non-test users, admin/IT-admin are privileged; other staff require a non-null active facility equal to the patient's facility.
- `has_role(uuid, app_role)` is a SECURITY DEFINER helper.

The repairs should preserve empty function search paths and use fully qualified object references. Do not weaken `assert_patient_facility_context` or move test-mode checks behind administrator checks.

## 3. Additional operational-workspace review still required

The live `get_operational_workspace` definition contains other branches with nullable facility predicates, including ward/bed and patient-linked workflows. The appointment branch is a confirmed NULL-context bypass, not proof that every other branch is safe. Before any replacement of the full function, review each branch's role allowlist, patient/record facility lineage, null-facility behavior, and test-mode semantics. Do not replace the full current body with an older collision candidate.

## 4. Default function EXECUTE ACL: live confirmation

A fresh `pg_default_acl` read confirms that the `public` schema defaults for both `postgres` and `supabase_admin` include EXECUTE for `anon` and `authenticated` on newly created functions. The same default pattern is also present for selected Supabase-managed schemas; this review does not propose changing managed-schema defaults.

**Required forward repair**
- Restrict the correction to the `public` schema and the two observed function owners.
- Revoke default EXECUTE from `PUBLIC`, `anon`, and `authenticated` for future functions.
- Preserve owner and service-role behavior where intended.
- Explicitly grant EXECUTE to authenticated only for reviewed client-facing RPCs whose bodies enforce authentication, role, facility, and test-mode boundaries.
- Add a live catalog regression check that verifies the resulting default ACL rows for both owners.
- Do not assume this changes privileges on existing functions; audit existing function ACLs separately.

The repository already has `scripts/default-function-execute-contract.mjs` and `scripts/live-default-function-privilege-audit-contract.mjs`, but the hosted catalog result shows the intended default-ACL repair is not reflected in the live project. Existing migration collision/version blockers must be resolved through provenance review before any old timestamp candidate is replayed.

## 5. Ward-bed admission FK follow-up

A fresh read-only orphan check returned **0** rows where non-null `ward_beds.admission_id` fails to reference `admissions.id`. This removes the observed orphan-data blocker but does not itself authorize a constraint change. Before adding the FK, confirm deletion semantics and legacy retention requirements; prefer a restrictive/no-action relationship for clinical admission history unless the data-retention owner explicitly approves another lifecycle.

The relationship exception remains registered until a forward-only migration is generated, replayed on a disposable PostgreSQL 17/Supabase environment, and generated types show the FK.

## 6. Verification gates before implementation or deployment

1. Recover the exact full live function bodies and compare them with repository callsites and current generated types.
2. Identify every UI/API caller of the four RPCs and verify it expects the same result shape.
3. Implement replacements as a new migration generated by `supabase migration new`, with a version later than the hosted ledger latest `20261026141054`; do not edit historical files.
4. Add regression cases for same-facility allow, cross-facility deny, null active-facility deny, mismatched parent/child facility deny, test-user isolation, and explicitly authorized admin context.
5. Verify default ACL behavior for both function owners and explicit grants for every intended RPC.
6. Replay both the existing-hosted upgrade path and clean-install path on disposable PostgreSQL 17/Supabase.
7. Run Supabase security advisors and the full Quality workflow; verify a new run on the final head.
8. Only then request review for deployment. No production DDL should be executed as part of this draft-PR documentation step.

## Disposition

**Confirmed security defects:** canteen, laboratory, imaging, and operational appointments facility scoping.

**Confirmed default-ACL gap:** future public-schema functions created by `postgres` or `supabase_admin` inherit EXECUTE for `anon` and `authenticated`.

**Confirmed data check:** zero orphaned non-null ward-bed admission references.

**Not done:** no SQL migration applied, no existing function replaced, no default ACL changed, no production deployment, no clean replay, and no CI result claimed.
