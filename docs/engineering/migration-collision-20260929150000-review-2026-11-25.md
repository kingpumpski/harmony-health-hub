# Migration collision review: 20260929150000

Updated: 2026-11-25

## Scope and decision

Reviewed all three candidates sharing version `20260929150000` against the canonical schema, RLS policies, function signatures, search paths and current facility-scoped columns:

- `20260929150000_canteen_dietary_operational_workspace.sql`
- `20260929150000_operational_workspace_scope_hardening.sql`
- `20260929150000_patient_canonical_insurer_linkage.sql`

All three feature areas exist live. The current patient-insurer RPC is more hardened than the candidate. The operational workspace functions have since been reworked and use empty search paths, but several SECURITY DEFINER read RPCs still omit facility filters. The canteen active-order RPC also returns patient/diagnosis/dietary context without facility scoping.

**Disposition:** preserve all three originals. Do not replay candidate function bodies. The highest-priority follow-up is a facility-boundary repair for canteen, laboratory and imaging workspaces, plus the appointment branch already documented in the 20260929103000 review.

## A. Canteen and dietary workspace

The canonical database contains `meal_menus`, `meal_menu_items`, `meal_orders`, and `meal_plans`. The two menu tables have RLS enabled, authenticated SELECT access, and no anon/direct authenticated write privileges. Their policies expose published menus only to callers accepted by `patient_can_read_meal_menus()`. The live menu schema has no facility_id, and the candidate defines a global uniqueness rule for date/meal period. Confirm with operations whether menus are intentionally global or should be facility-specific before changing that model.

The live `save_canteen_menu` RPC is authenticated-only, SECURITY DEFINER, and has a pinned search path. The live `get_canteen_active_patient_orders` RPC is SECURITY DEFINER with an empty search path and checks admin/canteen role. It returns patient names/codes, meal order details, dietary restrictions, chronic-condition context and current diagnoses.

### High-priority facility isolation gap

The live `get_canteen_active_patient_orders()` query filters by order status and scheduled time but does not compare:
- `meal_orders.facility_id` to the caller's active facility;
- `patients.facility_id` to the caller's active facility;
- `meal_plans.facility_id` to the same facility.

Those facility columns exist on meal orders, meal plans and patients. Because the function is SECURITY DEFINER, the facility RLS policies on `meal_orders` and `meal_plans` do not automatically constrain the function's joins. A canteen-role user can therefore receive cross-facility patient and diagnosis/dietary context through this RPC.

**Required repair:** require a non-null active facility for ordinary canteen staff and require patient, order and linked plan facility lineage to match. Define a narrowly documented admin override. Preserve the test-facility boundary. Add same-facility, cross-facility, no-active-facility, mismatched-parent, and privileged-role tests.

## B. Operational workspace scope hardening

The canonical database has separate SECURITY DEFINER workspace RPCs for laboratory, imaging, pharmacy and admissions, plus `get_operational_workspace(text,integer)`. All inspected live functions use empty search paths, which is stronger than the candidate's `pg_catalog, public` setting. Do not replay the candidate definitions just to restore their search paths.

### High-priority live facility gaps

1. **Laboratory workspace:** `get_laboratory_workspace(integer)` checks admin/lab-technician role and department, but its patient, lab-order and result queries do not constrain patient/order/result facility to the caller's active facility. It is SECURITY DEFINER, so table RLS does not supply the missing facility boundary.
2. **Imaging workspace:** `get_imaging_workspace(integer)` checks admin/radiologist/radiology-technician role and returns patient and imaging-order data without active-facility filtering. It is SECURITY DEFINER.
3. **Operational workspace appointments:** the current `get_operational_workspace` appointment branch has the NULL-context OR-condition defect documented in the 20260929103000 report: ordinary staff with no active facility can satisfy the branch's `v_facility IS NULL` condition and retrieve cross-facility appointments.
4. **Other operational modules:** inspect every module branch for fail-closed behavior when active facility is NULL and for patient/record facility lineage. The current admissions workspace explicitly requires an active facility for ordinary staff; the pharmacy workspace scopes patient/order data by active facility. Do not assume those protections extend to the separate lab, imaging, canteen or appointments functions.

The candidate's original workspace definitions are older and do not include the current facility helpers or test-user semantics. Replaying them would regress the live implementation.

## C. Patient canonical insurer linkage

The canonical `set_patient_insurance_company(uuid,uuid)` RPC exists, is SECURITY DEFINER with an empty search path, and is executable by authenticated but not anon. Compared with the candidate, the live body additionally calls `assert_patient_facility_context(_patient_id)` before locking and updating the patient. It validates that the selected company is active and records an audit event.

**Disposition:** retain the live facility-aware body. Do not restore the candidate's weaker `pg_catalog, public` function definition. The role allowlist (admin, IT admin, front desk, accountant) should remain governed by the application’s patient-insurance administration policy.

## Required next actions

1. Forward-repair `get_canteen_active_patient_orders` with patient/order/plan facility equality and a required active facility for ordinary canteen staff.
2. Forward-repair `get_laboratory_workspace` and `get_imaging_workspace` to require active facility and filter every patient/order/result to the same facility; preserve explicit admin selected-facility behavior.
3. Correct `get_operational_workspace` appointment NULL-context behavior and review all other module branches for the same pattern.
4. Add regression tests for same-facility success, cross-facility denial, no-active-facility denial, test-user isolation, and explicit privileged access for canteen, lab, imaging and operational workspace RPCs.
5. Confirm whether meal menus are global or facility-specific. If facility-specific, design an additive facility_id/unique-key migration with backfill and UI contract updates; do not guess the business rule.
6. Preserve empty search paths and current patient facility assertions in all live RPCs.
7. Reconcile migration source provenance and hosted ledger identities before resolving the duplicate timestamp.
8. Validate clean bootstrap and hosted-upgrade paths separately on disposable PostgreSQL 17/Supabase.

## Execution boundary

All inspection was read-only. No patient, diagnosis, dietary restriction, meal order, or meal plan row contents were queried. Only schema, function definitions, RLS policies, privileges and metadata were inspected. No SQL, ACL, policy, function, trigger, or migration ledger entry was changed. No historical migration was renamed, replayed, applied, or deleted. The collision remains unresolved.
