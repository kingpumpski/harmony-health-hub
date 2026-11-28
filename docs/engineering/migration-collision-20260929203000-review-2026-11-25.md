# Migration collision review: 20260929203000

Updated: 2026-11-25

## Scope and decision

Reviewed both candidates sharing version `20260929203000` against the canonical dashboard RPCs and current SECURITY DEFINER workspace search paths:

- `20260929203000_active_dashboard_role_context.sql`
- `20260929203000_harden_security_definer_read_workspace_paths_batch6.sql`

The role-specific dashboard RPC exists live and validates that the requested role is assigned to the authenticated user. The broad search-path batch is not reflected in the live catalog: most listed workspace/read functions retain an empty search path. Reapplying that batch would weaken the current configuration.

**Disposition:** preserve both originals. Keep the role-specific dashboard contract, but treat the dynamic source-text replacement as fragile. Do not apply the search-path batch as written.

## A. Active dashboard role context

The live `get_role_dashboard_summary_for_role(text)` exists as SECURITY INVOKER, executable by authenticated but not anon. It validates that `_requested_role` is actually assigned to `auth.uid()` before using that role; when no role is requested it falls back to the primary-role compatibility behavior. This is the intended multi-role dashboard context.

The candidate creates this function by calling `pg_get_functiondef('public.get_role_dashboard_summary()')` and performing exact string replacements. Its old role-selection snippet lists roles but does not include `system_superuser`. The current canonical source function includes `system_superuser` in its role allowlist. Therefore the candidate's exact old-snippet replacement will not match the current body; PostgreSQL string replacement silently leaves the old primary-role selection in place. The resulting function can be created successfully while ignoring `_requested_role`, which defeats the migration's purpose.

The live role-specific RPC contains the correct explicit `_requested_role` membership validation, so it must have been created from a compatible earlier source state or subsequently repaired. Do not infer that the current migration source is replay-safe from the live result.

**Required hardening:** replace dynamic text surgery with an explicit, reviewed function definition or a deterministic helper that takes the requested role and validates membership. Add a regression test proving a user with multiple roles can request each assigned role and is denied every unassigned role.

## B. SECURITY DEFINER read-workspace search paths batch 6

The candidate changes 14 read/workspace function search paths to `pg_catalog, public`. The canonical catalog shows most of these functions currently use an empty search path, including:
- `get_admission_workspace(integer)`
- `get_imaging_workspace(integer)`
- `get_laboratory_workspace(integer)`
- `get_maternity_workspace(integer,uuid)`
- `get_pharmacy_workspace(integer)`

`get_attending_patient_history(uuid,uuid)` is an exception and currently uses `pg_catalog, public`, consistent with its later facility-read assertion implementation.

An empty search path is more restrictive and deterministic for SECURITY DEFINER functions than adding the exposed public schema. Reapplying the batch would weaken the current functions' name-resolution boundary. Keep the empty path unless a function's explicit object-resolution requirements justify a reviewed change.

The candidate says it does not change function behavior, but search-path changes can alter object resolution and are security-relevant. Do not treat this as a harmless metadata-only migration.

## Required next actions

1. Preserve the live role-specific dashboard RPC and add assigned-role/unassigned-role regression tests.
2. Replace dynamic pg_get_functiondef string replacement with explicit SQL or a stable helper in a future migration; verify behavior on both clean bootstrap and hosted upgrade.
3. Preserve empty search paths for SECURITY DEFINER workspace functions. Keep the attending-history exception only with its facility-read assertion and ownership checks.
4. Add a CI/catalog contract that flags any SECURITY DEFINER function changed from empty search_path to a broader path without an explicit reviewed exception.
5. Continue the facility-scope repairs identified for canteen, laboratory, imaging, maternity and operational appointments; search-path hardening does not substitute for row-level facility authorization.
6. Reconcile candidate provenance and hosted ledger identity before resolving the duplicate timestamp.
7. Validate clean bootstrap and hosted-upgrade paths separately on disposable PostgreSQL 17/Supabase.

## Execution boundary

All inspection was read-only. No dashboard, user-role, patient, appointment or workspace row contents were queried. Only function definitions, ACLs and search-path metadata were inspected. No SQL, ACL, policy, function, trigger, or migration ledger entry was changed. No historical migration was renamed, replayed, applied, or deleted. The collision remains unresolved.
