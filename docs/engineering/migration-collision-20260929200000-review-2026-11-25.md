# Migration collision review: 20260929200000

Updated: 2026-11-25

## Scope and decision

Reviewed all three candidates sharing version `20260929200000` against canonical canteen RLS/realtime policies, role dashboard function, and PostgreSQL default ACLs:

- `20260929200000_fix_canteen_menu_rbac_realtime.sql`
- `20260929200000_role_dashboard_kpi_cleanup.sql`
- `20260929200000_secure_default_function_execute_privileges.sql`

The canteen menu and realtime policies are already functionally represented in the live database. The role dashboard is an evolved SECURITY INVOKER implementation and must not be replaced by the older candidate body. **The secure default-function-execute candidate is not reflected in the live default ACLs** for either postgres or supabase_admin, which remain permissive for anon/authenticated.

## A. Canteen menu and realtime RBAC

The live menu read helper `patient_can_read_meal_menus()` is SECURITY DEFINER with an empty search path. It permits admin/canteen users and limits patient access to patients with an active admission; other authenticated non-patient roles can read published menus. Current `meal_menus` and `meal_menu_items` SELECT policies require published status and this helper.

The live realtime policy on `realtime.messages` restricts the canteen operations topic to authenticated admin/canteen users. This matches the candidate's intended role/topic restriction.

The candidate additionally alters `has_role(uuid,app_role)` search_path. The live function already uses `pg_catalog, public` and denies EXECUTE to anon/authenticated. Do not weaken or unnecessarily replace the live helper.

**Disposition:** the menu and realtime access intent is present. Add regression tests for patient-with-active-admission, patient-without-active-admission, canteen/admin draft visibility, other authenticated staff, and realtime topic isolation. Preserve the canteen patient-data facility repair documented in the 20260929150000 review; menu visibility does not fix the cross-facility patient-order RPC.

## B. Role dashboard KPI cleanup

The live `get_role_dashboard_summary()` is SECURITY INVOKER and executable by authenticated but not anon. It has evolved beyond the candidate, including a system-superuser branch and additional role cases. The candidate body does not contain the complete current role contract.

Because it is SECURITY INVOKER, underlying table RLS applies to its dashboard queries. Do not replace the current function body with the older candidate. Review its KPI queries against each source table's facility RLS policy and test no-active-facility behavior. The current `search_path=public` should be kept under review; do not assume a function-body replacement is needed merely to adjust a search path.

## C. Secure default function EXECUTE privileges

The candidate intends to revoke default EXECUTE from PUBLIC, anon and authenticated for functions created by postgres and supabase_admin in public.

The live PostgreSQL default ACLs show that this change has **not** been applied:
- postgres/public function defaults still include EXECUTE for anon and authenticated;
- supabase_admin/public function defaults still include EXECUTE for anon and authenticated.

This means newly created public functions owned by either role can inherit client EXECUTE privileges unless each migration explicitly revokes them. Current sampled functions often have explicit anon revocations, but that does not fix the default for future functions.

**High-priority forward repair:** add a reviewed default-privilege migration for both owner roles, then add a CI/catalog contract that verifies PUBLIC/anon/authenticated are absent from the default function ACL. Before rollout, audit all migration-created RPCs to ensure intended authenticated functions explicitly GRANT EXECUTE after role/facility checks. This default ACL change does not revoke privileges from existing functions; existing function ACL review remains a separate task.

## Required next actions

1. Apply the secure-by-default function EXECUTE policy for postgres and supabase_admin through a new forward-only migration after disposable replay.
2. Add a default-ACL regression query/test and require explicit GRANT EXECUTE for intended client RPCs.
3. Preserve the current role dashboard implementation and verify RLS/facility behavior of each KPI source.
4. Keep the live canteen menu and realtime policies, with role/active-admission regression tests.
5. Reconcile all current SECURITY DEFINER function ACLs separately; do not assume default ACL changes retroactively secure existing functions.
6. Preserve the canteen active-order facility-boundary repair from the 20260929150000 review.
7. Reconcile original migration provenance and hosted ledger identity before resolving the duplicate version.
8. Validate clean bootstrap and hosted-upgrade paths separately on disposable PostgreSQL 17/Supabase.

## Execution boundary

All inspection was read-only. No patient, diagnosis, meal, notification, or dashboard row contents were queried. Only PostgreSQL default ACLs, function definitions/privileges, and RLS/realtime policy metadata were inspected. No SQL, ACL, policy, function, trigger, or migration ledger entry was changed. No historical migration was renamed, replayed, applied, or deleted. The collision remains unresolved.
