# Laboratory panel access and operational workspace follow-up — 2026-11-25

## Scope

This is a continuation of the canonical security review for hosted project `ygqoptvezotdqhtimdkr`. Inspection was read-only. No patient rows were queried, no SQL was applied, and no migration was deployed.

## 1. Laboratory panel table access: live grants contradict the migration

The canonical schema reports RLS enabled and zero policies on both:

- `public.lab_test_groups`
- `public.lab_test_group_items`

This is intentional: the application reads and writes panels through `get_laboratory_test_groups(boolean)` and `save_laboratory_test_group(...)`, both SECURITY DEFINER RPCs that require authentication, an active facility, and role checks. The UI component `src/components/laboratory/LabTestGroupsManager.tsx` calls those RPCs and does not directly query the panel tables.

The historical migration `20261015060000_reconcile_missing_laboratory_objects.sql` explicitly revokes table privileges from PUBLIC, anon, and authenticated. However, live `has_table_privilege` checks show that both anon and authenticated currently have SELECT, INSERT, UPDATE, and DELETE privileges on both tables. This is an ACL drift finding; the empty RLS policy set currently prevents ordinary client row access, but the table grants are broader than the intended RPC-only model.

**Forward repair required**
- Revoke all direct table privileges from PUBLIC, anon, and authenticated on both panel tables.
- Preserve owner/service-role privileges required for maintenance and controlled server-side workflows.
- Keep RLS enabled and do not add broad client policies just to clear the advisor's informational `rls_enabled_no_policy` warning.
- Verify the RPCs remain executable by authenticated users and retain active-facility and role enforcement.
- Add regression coverage for RLS enabled, zero direct client policies, and no direct client table privileges.

A static contract and pgTAP database contract have now been added to the branch. The pgTAP contract is expected to fail against the currently inspected hosted ACL state until a forward repair is applied and replayed.

## 2. Mutable trigger search_path

The live `public.ensure_updated_at()` trigger function has no function-level `search_path` setting. It is attached to:

- `public.lab_test_groups`
- `public.lab_test_group_items`
- `public.lab_orders`

Its body only assigns `NEW.updated_at` and returns `NEW`; it does not dynamically resolve application objects. Pinning its function configuration to an empty search path is appropriate and avoids a mutable caller-controlled path. PostgreSQL's implicit `pg_catalog` lookup continues to resolve built-in functions such as `now()`.

**Forward repair required:** `ALTER FUNCTION public.ensure_updated_at() SET search_path = ''`, followed by a catalog assertion that `pg_proc.proconfig` contains the empty search path and a trigger smoke test on each attached table.

## 3. Default function EXECUTE remains unresolved in the hosted project

The repository contains `20260929200000_secure_default_function_execute_privileges.sql`, with six intended default-privilege revocations for `postgres` and `supabase_admin`. The live `pg_default_acl` state for both owners still includes EXECUTE for anon and authenticated in schema public.

The migration version belongs to a duplicate-version collision group and is not reflected in the canonical state. Do not replay or rename that historical migration to force it through.

**Forward repair required:** create a new migration version later than the hosted ledger latest `20261026141054`, revoke default EXECUTE for PUBLIC, anon, and authenticated for both owners in schema public, then explicitly grant EXECUTE to reviewed client-facing RPCs where needed. This does not change privileges on existing functions; those require a separate exact-signature audit.

A new pgTAP contract now checks the two owners' public-schema default ACLs. It is expected to fail against the current hosted state until the forward repair is applied.

## 4. Operational workspace: additional facility-boundary defects

The full live definition of `public.get_operational_workspace(text,integer)` confirms the appointments branch uses a predicate equivalent to:

```sql
v_role IN ('admin','it_admin','system_superuser')
OR v_facility IS NULL
OR p.facility_id = v_facility
```

For ordinary staff with a null active facility, the middle condition is true and the query becomes cross-facility. The branch joins appointments to patients but does not additionally require `appointments.facility_id` to match the patient and active facility.

The ward and bed branches also include `facility_id IS NULL` rows for all callers. This makes unassigned/global rows visible to ordinary staff with a selected facility, and the administrator/null-facility expression is not a clean explicit global-access contract.

**Forward repair required**
- Fail closed for non-platform staff when no active facility is selected before any patient/operational workspace query.
- For appointments, require appointment and patient facility IDs to agree with the selected facility for ordinary staff.
- For wards and beds, require an explicit shared/global-data policy for null-facility rows; otherwise scope them to the active facility.
- Define platform-administrator behavior explicitly: selected-facility mode should scope by default; global access should be an explicit, audited capability rather than an accidental consequence of a null facility.
- Review each module branch's record facility and patient facility lineage before replacing the full function. Preserve role and department filters and all response keys used by the existing UI.
- Add tests for null facility, selected facility, mismatched parent/child facility, legacy null-facility records, platform admin selected-facility mode, and any approved global mode.

The same live function includes additional patient-linked branches. A full replacement must be built from the exact live body and checked branch-by-branch; do not restore an older collision candidate.

## 5. Repository changes in this continuation

Added:
- `scripts/lab-panel-access-model-contract.mjs`
- `supabase/tests/database/laboratory_panel_access_model_contract.sql`
- `scripts/default-function-acl-database-contract.mjs`
- `supabase/tests/database/default_function_acl_contract.sql`

Updated:
- `package.json` to run both static contracts in the aggregate test script.
- `.github/workflows/quality.yml` to execute both static contracts.

These changes protect the intended access model and add database regression tests; they do not themselves alter hosted ACLs or function definitions.

## 6. Verification and blockers

- Read-only catalog inspection confirmed the current panel table ACLs, empty RLS policies, trigger search_path, and default function ACLs.
- Static contract conditions were checked against the repository source and are internally consistent.
- No local Supabase CLI, PostgreSQL client, Docker, or Podman binary is available in this execution environment. Therefore the pgTAP contracts and migrations cannot be replayed here.
- No new Quality workflow run was returned at the time of this report. Do not treat the CI gate as passed.
- The PR remains draft and unmerged.

## Disposition

**Implemented in repository:** static CI contracts and database pgTAP regression tests for laboratory panel access and default function ACLs.

**Confirmed but not repaired in hosted database:** panel direct table grants, mutable `ensure_updated_at` search_path, default function EXECUTE defaults, and operational workspace facility scoping.

**Next implementation gate:** generate forward-only migration(s) with `supabase migration new` in a proper Supabase CLI environment, replay against disposable PostgreSQL 17/Supabase, run pgTAP and advisors, then obtain a fresh Quality run on the final branch head. Do not deploy to canonical until those gates pass.
