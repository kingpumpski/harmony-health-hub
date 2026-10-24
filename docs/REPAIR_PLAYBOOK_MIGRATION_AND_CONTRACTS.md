# Database Migration and Contract Repair Playbook

Use this playbook as an execution contract whenever migration replay, schema/security contracts, or operational contract checks fail. Apply the prompts in order, inspect the repository rather than relying on a pasted error alone, and report evidence for every claimed fix.

## Shared rules for every repair

1. Work from the latest `main` and current failing check run. Inspect full source files, migration order, canonical schema definitions, app callers, and relevant CI workflow.
2. Fix the cause, not the symptom. Do not silence SQL errors, create duplicate tables, weaken an assertion, skip a failing test, or make a required schema object optional just to pass CI.
3. Historical migration edits are allowed only when required for deterministic clean replay; when an installation may already have recorded the old migration, add an idempotent forward repair where needed and explain the compatibility choice.
4. Preserve existing records. Never infer or silently backfill clinical ownership, facility attribution, payment state, acknowledgement state, or other business data.
5. Do not push schema changes to the connected/live Supabase project. Use disposable local Supabase replay and test fixtures. Live changes require explicit authorization.
6. Keep authorization boundaries intact: qualify schema objects, pin `search_path` on privileged functions, verify RLS and grants, and do not expose `service_role` credentials.
7. For local test hosting, GitHub Pages is the designated path. A Vercel preview/deployment failure is non-blocking unless that exact check is explicitly required by branch protection. This does not waive Quality, migration replay, schema/security, or database contract checks.
8. After each repair, run the narrow test first, then the relevant full contract suite, then a clean migration replay. Commit logically separate fixes separately. Do not claim success without actual output from the current head.

## Prompt 1 — Repair the clinical facility unresolved-record query

**Symptom:** `public.list_unresolved_clinical_facility_records(integer)` fails because `public.lab_results` has no `patient_id` column.

- Read the complete migration defining the function and inspect the canonical schemas for `lab_results`, `lab_orders`, and `encounters`.
- Trace the actual lineage. Prefer `lab_results.lab_order_id -> lab_orders.id -> lab_orders.patient_id` if that is the canonical relationship; do not assume it without checking the schema and constraints.
- Derive the patient ID through a correctly schema-qualified join (normally a LEFT JOIN to `public.lab_orders`) so orphaned historical results remain visible with a NULL patient ID rather than disappearing.
- Verify every UNION branch has exactly five columns with types matching `(entity_type text, entity_id uuid, patient_id uuid, created_at timestamptz, metadata jsonb)`; preserve metadata keys and the existing authorization contract.
- Search all application callers and tests for the RPC and confirm `patient_id` remains meaningful.
- Run a clean local replay and the facility-reconciliation contract. Report the SQL diff, canonical linkage rationale, and exact command output.

## Prompt 2 — Restore the AI diagnosis/reference schema before RLS hardening

**Symptom:** migration `20260910215228_81137334-9a88-408e-b7f3-0993eb7b9918.sql` fails because `public.ai_diagnosis_suggestions` does not exist.

- Inspect migrations `20260910215225` through `20260910215228`, the entire migration tree, generated Supabase types, application usage, and foreign-key/index migrations.
- Determine the canonical schema and intended migration order for `audit_logs`, `sync_queue`, `lab_tests`, `ai_symptom_icd_map`, and `ai_diagnosis_suggestions`. Verify referenced tables and key types exist at the creation point.
- If a required table is missing, restore its canonical creation/reconciliation migration before the first RLS, grant, policy, index, or foreign-key reference. Do not merely wrap required-table RLS in `IF to_regclass(...) IS NOT NULL`; that hides the missing schema. Optional views may be guarded when legacy installations legitimately lack them.
- Reconcile columns and constraints idempotently without duplicating tables or discarding records. Keep RLS and least-privilege grants consistent with the intended access model.
- Run migration filename/ordering contracts, a fresh `supabase db reset`, database contract SQL, and schema/security contracts. Report the exact failure progression and the final replay output.

## Prompt 3 — Make the facility-access policy rewrite safe and deterministic

**Symptom:** migration `20260925234500_fix_facility_access_policy_execution_boundary.sql` raises `Unrecognized has_facility_access policy expression`, including for `healthcare_facilities.healthcare_facilities_access`.

- Inspect the complete migration and the exact `pg_policies.qual` / `with_check` expression produced by the preceding policy migration. Verify `public.current_user_has_facility_access(uuid)` exists and inspect `pg_proc.prosecdef` and `proconfig` to confirm its security-definer and pinned-search-path properties.
- Rewrite only two-argument `has_facility_access` calls bound to the current authenticated `auth.uid()`. Account for PostgreSQL deparse differences such as omitted `AS uid`, case, whitespace, schema-qualified or quoted column identifiers, and harmless casts. Keep argument capture groups correct.
- Handle `healthcare_facilities.healthcare_facilities_access` explicitly using `public.current_user_has_facility_access(id)` if the generic rewrite cannot safely preserve its expression.
- Do not silently leave a client-facing policy calling the low-level helper. Unknown expressions should be surfaced clearly and explicitly resolved; the final verification must fail if a direct low-level helper call remains in an exposed public policy.
- Preserve policy command semantics (`USING` vs `WITH CHECK`) and existing predicates. Keep the helper internal-only and the authenticated-session wrapper appropriately granted.
- Run clean replay and query `pg_policies` to show that no public policy still calls the low-level helper. Include the query and results.

## Prompt 4 — Repair operational contract failures without weakening contracts

**Symptoms:** failures name the laboratory payment-release gate and notification-bell acknowledgement behavior.

- Read `scripts/validate-operational-contracts.mjs`, `scripts/specialist-assessment-entry-contract.mjs`, relevant test scripts, `src/pages/Laboratory.tsx`, the laboratory workspace RPC/migrations, `src/components/layout/Header.tsx`, notification RPCs, and notification migrations.
- For laboratory orders, trace the full order lifecycle from encounter/service order and invoice through Accounts release to worklist visibility, sample collection, result entry, and approval. Confirm the server-authoritative service-order release state is the gate; a UI message alone is not enforcement. Check that encounter-originated orders cannot be processed while payment is pending, while legitimate explicitly non-billable orders retain their intended behavior.
- For notifications, confirm fetch/render/subscription does not mark notifications read. Bell attention must be derived from unread rows and persist until the authenticated user explicitly acknowledges/marks them read. Verify the RPC enforces recipient authorization and updates only the intended notification.
- Fix product code or SQL when behavior is wrong. If a contract is stale, change the assertion only when repository evidence proves the documented behavior has intentionally changed; update the behavior and contract together and explain why.
- Run the two targeted contract scripts, then `npm run test:contracts` and the full quality suite. Include complete output and the exact diff for any contract assertion change.

## Prompt 5 — Reduce container image rate-limit noise without masking SQL failures

**Symptom:** CI image pulls hit registry rate limits before the useful migration error is visible.

- Inspect `supabase/config.toml`, the pinned Supabase CLI version, workflow image-pull logs, and the actual image names/tags selected by the CLI. Do not assume changing `config.toml` supports arbitrary registry overrides; verify against the installed CLI and Supabase docs.
- Prefer supported authenticated pulls or a supported cache/mirror. If using a registry login, use an existing least-privilege secret, never print credentials, and do not add a new secret dependency without documenting setup. Verify the referenced images and explicit tags actually exist.
- Keep `set -o pipefail`, print captured startup logs, retry only transient network/rate-limit failures with bounded backoff, and stop immediately on deterministic SQLSTATE/schema/syntax/migration failures.
- Validate with a CI run showing image startup and the real migration result. Do not treat fewer retries as a migration fix.

## Required execution order

1. Fix the first deterministic clean-replay blocker (including missing prerequisite schemas).
2. Fix the facility-policy rewrite before it can conceal or break RLS security boundaries.
3. Re-run clean replay to reveal the next actual blocker; repeat until the full chain succeeds.
4. Run database and schema/security contracts.
5. Run operational contract tests and the full quality suite.
6. Review current PR heads and merge only non-draft, conflict-free PRs whose required quality, database/security, and Pages checks pass. Vercel is non-blocking under the rule above.

For every step, report changed files/commit, root cause, checks executed, exact pass/fail output, remaining blockers, and whether the check is from the current head. Never describe a partial replay or an old green run as proof that the current migration chain passes.
