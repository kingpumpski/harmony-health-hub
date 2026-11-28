# Supabase advisor snapshot and triage — 2026-11-25

Observed: 2026-11-25 12:48 UTC, hosted project `harmony-health-hub` (`ygqoptvezotdqhtimdkr`). Advisor calls were read-only. No SQL, data, or configuration was changed.

## Security advisor

| Finding | Count | Triage |
|---|---:|---|
| RLS enabled, no policies | 2 | Confirmed on `public.lab_test_group_items` and `public.lab_test_groups`. Their intended access model must be decided before adding policies; broad permissive policies would be unsafe. |
| Mutable function search_path | 1 | `public.ensure_updated_at()`. Pin to an empty or otherwise explicitly safe search path after checking trigger dependencies and callers. |
| Authenticated SECURITY DEFINER functions executable | 279 | Inventory warning, not proof that all 279 are vulnerable. Review exact signatures, caller/UI usage, role checks, facility checks, test-mode checks, and function ownership individually. Do not apply a bulk EXECUTE revoke. |

The 279-function warning set is especially important to triage because SECURITY DEFINER functions bypass ordinary RLS. Intended client RPCs can remain authenticated-callable when their bodies enforce authorization and data scope; internal helpers should not be exposed. Review should produce an exact-signature allowlist/denylist and tests, not a global policy based only on the advisor count.

Remediation references:
- [RLS enabled without policies](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy)
- [Mutable function search_path](https://supabase.com/docs/guides/database/database-linter?lint=0011_function_search_path_mutable)
- [Authenticated SECURITY DEFINER exposure](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable)

## Performance advisor

| Finding | Count | Triage |
|---|---:|---|
| Multiple permissive policies | 12 | Consolidate only after verifying policy semantics and role coverage. Preserve patient-self access and staff facility access as distinct tested cases. |
| Duplicate index | 1 | `public.lab_result_attachments` has equivalent indexes `idx_lab_result_attachments_lab_result_id` and `lab_result_attachments_result_idx`. Confirm constraints/dependencies and query plans before dropping one. |

The 12 multiple-permissive-policy findings include SELECT policies on appointments, invoices, video sessions, payroll tables, and specialist/assessment tables. Multiple permissive policies are OR-combined, so consolidation must preserve intended row visibility; never replace them with a narrower policy based only on the warning.

Duplicate index remediation reference:
- [Duplicate indexes](https://supabase.com/docs/guides/database/database-linter?lint=0009_duplicate_index)

## Execution decision

No advisor finding is fixed by changing the live database in this step. Prioritize the confirmed facility-isolation defects in the separate canonical facility-isolation review, then repair the two laboratory RLS/no-policy findings and mutable trigger search_path with forward-only migrations. The existing migration chain's duplicate-version and clean-replay blockers remain in force.

## Verification status

- Advisor snapshot obtained successfully.
- No migration generated or applied.
- No existing function EXECUTE privileges changed.
- No RLS policy changed.
- No index dropped.
- No clean replay or CI run triggered by this documentation-only commit.
