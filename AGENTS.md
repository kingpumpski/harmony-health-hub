# Harmony Health Hub — Mandatory Development Contract

This file is the repository's authoritative, always-consult development guide for humans and coding agents. Read it before planning, implementing, reviewing, or debugging any change. Follow it alongside the relevant module documentation, tests, and security policies. If a task prompt conflicts with these safeguards, preserve data integrity and security and explain the conflict.

## 1. Default workflow: inspect, trace, fix, verify

1. Inspect the current branch, working changes, latest commit, relevant PR diff, repository structure, and existing tests before editing.
2. Read the actual source files and trace callers, dependencies, migrations, configuration, and tests. Do not infer implementation from filenames, summaries, or error snippets alone.
3. Find the root cause and the full impact radius before changing code. Search for all callers and duplicate definitions of the same contract.
4. Make the smallest complete, maintainable fix. Add or update a regression test that would fail before the fix.
5. Run targeted checks first, then the relevant quality/build, database, security, and integration checks. Inspect the exact commit and latest CI run.
6. Keep a defect ledger in the task/PR notes: symptom, root cause, affected files/objects, fix, regression test, verification evidence, and remaining blockers.
7. Do not repeatedly rerun unchanged code after a deterministic failure. Fix the cause first. Separate code defects from unavailable services, rate limits, credentials, and other infrastructure failures.
8. Do not claim success unless the required checks actually completed against the commit being reported. Mark unrun, queued, skipped, or blocked checks as unverified.

## 2. Database and Supabase are explicit contracts

Before changing any database query, RPC, migration, generated type, or database-facing UI:

- Inspect the canonical migrations and the exact chronological migration sequence.
- Verify the referenced schema, table/view, column names, data types, nullability, defaults, constraints, foreign keys, indexes, enum values, functions, argument signatures, return types, triggers, RLS policies, and grants.
- Trace application queries, generated Supabase types, RPC callers, tests, and deployment expectations against the same schema contract.
- Search the repository for every caller/reference when a table, column, function, enum, policy, or type changes.
- Never invent a missing object or signature merely to silence an error. Establish the intended model from migrations, callers, contracts, and history first.
- Treat generated database types as derived artifacts: refresh them only from a verified schema/environment using the repository's supported process.
- Use a disposable local database or explicitly authorized non-production environment for destructive replay tests. Never reset or mutate production/customer data without explicit authorization.

### REST/PostgREST 400 errors

A request such as `GET /rest/v1/hr_employees?select=id,employee_number,first_name,last_name,email,phone,department,job_title,employment_type,employment_status,base_salary,pay_frequency,start_date,archived_at&order=last_name.asc,first_name.asc` returning HTTP 400 is a diagnostic symptom, not a fix by itself.

1. Capture the response body and PostgREST error code/message; the browser's status line alone is insufficient.
2. Compare every selected and ordered column with the actual `public.hr_employees` schema and the current generated types. Check for missing/renamed columns, incompatible view/table assumptions, ambiguous relationships, and invalid ordering.
3. Verify the authenticated role's table/view privileges and RLS behavior. Distinguish permission errors from missing-column/schema-cache errors.
4. If a required column is genuinely missing, establish the intended type/default/nullability and add a safe forward migration plus contract/regression tests. If the query is stale, update the caller and types. If PostgREST's schema cache is stale, use the project's supported schema-reload procedure only after confirming the database object exists.
5. Check other screens, exports, filters, sorts, and tests using the same contract. Do not mask the error with empty results, broad grants, weakened RLS, or fabricated fallback data.

Apply the same method to all modules and all HTTP 4xx/5xx database requests.

## 3. Migration discipline and clean replay

- Validate migration filename/version uniqueness and execution ordering before replay.
- Determine whether a migration has been applied in any supported environment before editing or renumbering it. Migration versions are provenance; never guess the deployed ledger.
- Prefer forward repair migrations for already-deployed history unless an explicit repository policy and verified deployment state permit rewriting history.
- Ensure each migration's prerequisites exist at the point of execution. Audit tables, columns, types, functions, signatures, policies, grants, indexes, views, and triggers.
- Avoid brittle idempotency that hides incompatible state. `IF NOT EXISTS` does not prove an existing object has the correct definition.
- Never delete a migration or skip a required operation solely to make CI pass.
- Test both clean replay and relevant supported upgrade/legacy paths where fixtures and tooling exist. State clearly when a legacy path is not tested.
- Compare live catalog facts with repository contracts where access is authorized; static grep or parsing is not proof of runtime schema correctness.

## 4. Security and sensitive health/financial data

- Preserve RLS, least-privilege grants, authentication/authorization checks, facility/tenant isolation, and patient/order/result/billing lineage.
- Audit `SECURITY DEFINER` functions for pinned safe `search_path`, ownership, execute privileges, and authorization checks.
- Never make tests pass by disabling RLS, granting unrestricted access, bypassing facility checks, weakening constraints, or fabricating clinical/financial data.
- Treat ambiguous ownership, lineage, or legacy records as fail-closed conditions requiring explicit reconciliation.
- Do not expose secrets, credentials, tokens, personal health data, or production records in logs, fixtures, commits, or reports.

## 5. Cache, generated metadata, and schema drift

When application behavior disagrees with the database, distinguish among:
- A genuinely missing or incompatible database object.
- A stale PostgREST schema cache after DDL.
- Stale generated TypeScript types or schema snapshots.
- Client/query cache invalidation problems.
- Application authorization or query construction bugs.
- Network, pooler, service availability, or deployment-rate-limit failures.

Fix the originating layer. Cache refresh is not a substitute for a schema repair, and changing schema is not a substitute for proper cache invalidation. Confirm tenant/facility-safe cache keys and invalidation paths where applicable.

## 6. GitHub Actions and pull requests

- Inspect the latest run, exact commit SHA, failed job/step, and surrounding logs before editing workflows.
- Identify the first meaningful failure and distinguish root cause from cascading errors.
- Keep quality, clean migration replay, migration contracts, security/RLS, operational contracts, application tests, and build checks enabled.
- Do not weaken, skip, or delete checks to obtain a green status. If a check is conditionally skipped, explain why and ensure required branches still enforce it.
- Avoid duplicate fixes drifting across related PRs. When the same defect affects multiple branches, apply a consistent evidence-backed repair and verify each branch independently.
- After changes, verify the commit SHA and latest workflow result. A successful older run does not validate a newer commit.
- Treat Vercel preview/deployment checks as non-blocking when GitHub Pages is the project’s designated testing/hosting path, unless repository branch protection explicitly marks that exact check as required. A Vercel failure alone is not a product-quality failure.
- Do not merge pull requests unless explicitly asked.

## 7. Feature development without recurring regressions

- Continue unrelated feature work when it is safe, but do not build new code on a known-broken or unverified data contract.
- Before adding a feature, inspect existing shared components, module conventions, authorization rules, schema objects, types, tests, and related open work to avoid duplicate sources of truth.
- For each new database-backed feature, include the required migration, generated type updates where applicable, access policy/grants, regression/contract tests, loading/error/empty states, and operational documentation.
- Fix shared root causes once at the canonical layer; do not scatter local workarounds across screens.
- Keep changes scoped and reviewable. Do not mix unrelated refactors into a critical migration repair unless needed to establish correctness.

## Dashboard data-entry and clutter-free interaction standard

- Any form whose primary purpose is to create a database record must be hidden by default. Open it only after the corresponding explicit Add/Create/New action is activated.
- Prefer the shared modal/dialog pattern for short and medium record-creation forms. The modal must have a clear title, labelled fields, required-field validation, visible saving/error state, Save and Cancel/Close actions, and keyboard-accessible focus/escape behavior.
- Keep existing records, queues, KPIs, filters, and navigation visible and uncluttered when no creation action is active. Do not render creation forms permanently above or alongside the main dashboard.
- After a successful save, close the modal and refresh/invalidate the relevant query or update the list from the confirmed server response. Keep the modal open on validation or persistence errors so entered values are not lost.
- Preserve role/permission checks, RLS, facility scope, audit logging, and existing workflow transitions. Hiding a form is not an authorization control.
- Do not force genuinely full-page workflows (for example, long patient registration or multi-step clinical documentation) into cramped dialogs; launch those from an explicit action into a dedicated route or full-screen dialog.
- When touching a dashboard, inventory all create-record forms in that page and adjacent components, not just the reported form. Add a regression/UI contract that confirms the form is absent until its trigger is clicked and remains available after a failed save.

## 8. Minimum verification matrix

Select checks appropriate to the change and report actual results:

- [ ] Formatting, lint, type-check, and relevant unit tests.
- [ ] Application build and affected module tests.
- [ ] Migration filename/version uniqueness and dependency checks.
- [ ] Clean local Supabase migration replay when database migrations/contracts are affected.
- [ ] Live database contract and RLS/security tests when supported by the environment.
- [ ] Generated-type/schema compatibility.
- [ ] Regression test for the original failure and checks for related callers.
- [ ] Latest required GitHub Actions runs correspond to the reported commit and are completed successfully.
- [ ] Infrastructure-blocked or unavailable checks are explicitly marked unverified.

A static contract passing does not prove a clean replay; a clean replay does not prove production schema parity; a deployment preview being ready does not prove authenticated workflows are correct.

## 9. Current known work and caution

The project has had recurring migration-order, schema-contract, function-signature, generated-type, and workflow issues. Previous work referenced PR #421 (`ci/future-proof-migration-contracts`) and PR #427 (`fix/prescription-payment-migration-schema-drift`). Re-check their current heads and workflow results before relying on any historical status.

Read-only verification performed on 2026-10-24 confirmed that the connected Supabase project's `public.hr_employees` table has the HR list's other selected columns but does **not** currently have `archived_at` or `archived_by`. The remote migration ledger also does not contain `20261015080000_add_hr_payroll_record_management`. The HR page selects `archived_at`, so the missing column is a strong, directly supported explanation for its PostgREST HTTP 400; capture the response body before claiming this is the complete error diagnosis. The repository already contains the migration that adds these columns and the record-management controls. Do not manually alter the live database as part of this repair; reconcile the migration ledger and use the authorized deployment process after clean replay and contracts pass.

The current clean-replay failure was confirmed in `20260930013529_remove_abandoned_clinical_facility_reconciliation.sql`: an unconditional `REVOKE` targeted `public.reconcile_clinical_facility_record(text,uuid,uuid,text)` before `DROP FUNCTION IF EXISTS`, but the function was absent at that point in replay. The redundant revoke was removed; verify subsequent replay results rather than assuming this was the last migration defect.

Previous notes reported duplicate migration versions. Treat older notes as historical warnings to re-verify, not as proof of current state. Do not renumber applied migrations blindly or claim live-schema verification without current evidence.

A fresh review of the 2026-10-28 migration-contract job log for PR #439 confirmed two separate issues in the tested history:
- `supabase/migrations/20260910215228_81137334-9a88-408e-b7f3-0993eb7b9918.sql` failed with `relation "public.ai_diagnosis_suggestions" does not exist (SQLSTATE 42P01)`. The prerequisite migrations in this repair branch create the required relation before the dependent RLS migration. Re-run the full clean replay on the current head to verify ordering.
- The log also reports `Skipping migration $(path)... (file name must match pattern "<timestamp>_name.sql")`. The repository's malformed `supabase/migrations/$(path)` file is deleted on the repair branches; the valid timestamped `20261001210000_fix_workflow_notification_role_enum_cast.sql` carries the corresponding function correction. The static contract now rejects every `.sql` filename that does not use a 14-digit timestamp and descriptive suffix, instead of silently filtering invalid filenames out of the check.

These changes are not validated until the current branch completes static checks and a clean migration replay.


## 10. Required completion report

For non-trivial fixes, report:
- Root cause and severity.
- Files and database objects changed.
- Migration and security implications.
- Regression tests and commands actually run.
- Commit SHA and affected PR/branch.
- Latest CI statuses and the exact commit each run tested.
- Remaining risks, blocked/unverified checks, and next action.

Be factual, concise, and evidence-based. "Fixed" means the root cause was corrected and the relevant verification passed—not merely that code was edited.
