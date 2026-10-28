# Harmony Health Hub — Mandatory Development Contract

This is the repository's authoritative guide for humans and coding agents. Read it before planning, implementing, reviewing, or debugging changes. Preserve patient safety, data integrity, tenant/facility isolation, and least-privilege security even when a task prompt or failing check creates pressure to take shortcuts.

## 1. Default workflow: inspect, trace, fix, verify

1. Inspect the current branch, working changes, latest commit, relevant PR diff, repository structure, and existing tests before editing.
2. Read actual source files and trace callers, dependencies, migrations, configuration, and tests. Do not infer implementation from filenames, summaries, or isolated error snippets.
3. Identify the root cause and impact radius. Search for all callers and duplicate definitions of the affected contract.
4. Make the smallest complete, maintainable fix and add/update a regression test that would fail before the fix.
5. Run targeted checks first, then relevant quality/build, database, security, and integration checks.
6. Keep a defect ledger in task/PR notes: symptom, root cause, affected files/objects, fix, regression test, verification evidence, and remaining blockers.
7. Do not repeatedly rerun unchanged code after a deterministic failure. Fix the cause first. Separate code defects from unavailable services, rate limits, credentials, and infrastructure failures.
8. Never claim success unless the required checks actually completed against the commit being reported. Mark unrun, queued, skipped, or blocked checks as unverified.

## 2. Database and Supabase contracts

Before changing a database query, RPC, migration, generated type, or database-facing UI:

- Inspect canonical migrations and the exact chronological migration sequence.
- Verify table/view/function names, column names, types, nullability, defaults, constraints, foreign keys, indexes, enum values, RPC argument and return types, triggers, RLS policies, and grants.
- Compare the same contract against application queries, generated Supabase types, RPC callers, tests, and deployment expectations.
- Search the repository for every caller/reference when a database object or type changes.
- Never invent a missing object or signature merely to silence an error. Establish the intended model from migrations, callers, contracts, and history first.
- Do not assume `IF NOT EXISTS` makes an existing object compatible; inspect its definition.
- Treat generated database types as derived artifacts. Refresh them only from a verified schema/environment using the repository's supported process.
- Use a disposable local database or explicitly authorized non-production environment for destructive replay tests. Never reset or mutate production/customer data without explicit authorization.

### REST/PostgREST 400 errors

1. Capture the response body and PostgREST error code/message; a browser status line alone is insufficient.
2. Compare every selected, filtered, joined, and ordered column with the actual table/view schema and generated types.
3. Verify privileges and RLS, distinguishing authorization failures from missing-column/schema-cache errors.
4. If a required column is missing, establish its intended type/default/nullability and add a safe migration plus regression contract. If the query is stale, update the caller and types. Refresh schema cache only after confirming the database object exists.
5. Check other screens, exports, filters, sorts, and tests using the same contract. Never mask errors with empty results, broad grants, weakened RLS, or fabricated fallback data.

## 3. Migration discipline and clean replay

- Validate migration filename/version uniqueness and execution order before replay.
- Determine whether a migration has been applied in supported environments before editing or renumbering it. Migration versions are provenance; never guess the deployed ledger.
- Prefer forward repair migrations for already-deployed history unless repository policy and verified deployment state permit rewriting history.
- Ensure every prerequisite exists at the point it is used: tables, columns, types, functions, signatures, policies, grants, indexes, views, and triggers.
- Cross-check every referenced object against the schema that actually exists at that point in the migration chain. Do not copy object or column names from a stale schema variant.
- Avoid brittle idempotency that hides incompatible state. `IF NOT EXISTS` does not prove an existing object has the correct definition.
- Never delete a migration or skip a required operation solely to make CI pass.
- Test clean replay and supported upgrade/legacy paths where fixtures and tooling exist. Clearly state when a path is not tested.
- Static parsing is not proof of runtime schema correctness. Verify database catalog facts only in an authorized environment.
- Preserve established PostgreSQL function/procedure argument and return-type contracts across the entire migration chain. `CREATE OR REPLACE FUNCTION` cannot change an existing function's return type; reconcile duplicate definitions and callers, and use an explicit drop/recreate only when dependency and compatibility impact is understood and safely migrated.
- Do not edit live databases during repository repair without explicit authorization.

### PL/pgSQL dollar-quote integrity (mandatory)

- Every SQL function/procedure block using a dollar-quote delimiter must close with the exact same delimiter used to open it (for example, `AS $claim_financials$ ... $claim_financials$;`).
- Bare `$;` terminators are prohibited. Never substitute `$`, `$;`, or another tag for a named opener.
- Before migration replay, run `node scripts/check-plpgsql-delimiters.mjs`. The Migration contract workflow must run this validator before starting Supabase.
- Treat a delimiter failure as a deterministic SQL defect: fix the reported migration and rerun the validator before retrying service startup.
- This validator is a preflight, not a replacement for `supabase db reset`, database contract tests, or runtime schema verification.

## 4. Security and sensitive health/financial data

- Preserve RLS, least-privilege grants, authentication/authorization checks, facility/tenant isolation, and patient/order/result/billing lineage.
- Audit `SECURITY DEFINER` functions for a pinned safe `search_path`, ownership, execute privileges, and authorization checks.
- Never make tests pass by disabling RLS, granting unrestricted access, bypassing facility checks, weakening constraints, or fabricating clinical/financial data.
- Treat ambiguous ownership, lineage, or legacy records as fail-closed conditions requiring explicit reconciliation.
- Do not expose secrets, credentials, tokens, personal health data, or production records in logs, fixtures, commits, or reports.

## 5. Cache, generated metadata, and schema drift

Distinguish among a genuinely missing/incompatible database object, stale PostgREST schema cache, stale generated types, client/query cache invalidation, authorization/query construction bugs, and network/pooler/service/deployment failures. Fix the originating layer. Cache refresh is not a substitute for schema repair, and changing schema is not a substitute for cache invalidation. Confirm tenant/facility-safe cache keys and invalidation paths.

## 6. GitHub Actions and pull requests

- Inspect the latest run, exact commit SHA, failed job/step, and surrounding logs before editing workflows.
- Identify the first meaningful failure and distinguish root cause from cascading errors.
- Keep quality, clean migration replay, migration contracts, security/RLS, operational contracts, application tests, and build checks enabled.
- Do not weaken, skip, or delete checks to obtain a green status. Explain conditional skips and ensure required branches still enforce the contract.
- When the same defect affects multiple branches, apply consistent evidence-backed repairs and verify each branch independently.
- After changes, verify the commit SHA and latest workflow result. A successful older run does not validate a newer commit.
- Treat Vercel preview/deployment checks as non-blocking when GitHub Pages is the designated testing/hosting path, unless branch protection explicitly marks that exact check as required. A Vercel failure alone is not a product-quality failure.
- Do not merge pull requests unless explicitly asked.

## 7. Feature development without recurring regressions

Continue unrelated feature work when safe, but do not build on a known-broken or unverified data contract. Before adding a feature, inspect shared components, module conventions, authorization, schema, types, tests, and related open work. Each database-backed feature should include required migrations, access policies/grants, generated-type updates where applicable, regression/contract tests, loading/error/empty states, and documentation. Fix shared root causes at the canonical layer instead of scattering workarounds.

## 8. Minimum verification matrix

Select checks appropriate to the change and report actual results:

- [ ] Formatting, lint, type-check, and relevant unit tests.
- [ ] Application build and affected module tests.
- [ ] Migration filename/version uniqueness and dependency checks.
- [ ] Clean local Supabase migration replay when migrations/contracts are affected.
- [ ] Live schema, RPC, privileges, RLS/security, and HR/payroll contracts when supported.
- [ ] Generated-type/schema compatibility.
- [ ] Regression test for the original failure and checks for related callers.
- [ ] Latest required GitHub Actions runs correspond to the reported commit and completed successfully.
- [ ] Infrastructure-blocked or unavailable checks explicitly marked unverified.

A static contract passing does not prove clean replay; clean replay does not prove production schema parity; a deployment preview does not prove authenticated workflows are correct.

## 9. Known recurring project risks

- The project has had migration-order, schema-contract, function-signature, generated-type, and workflow issues. Re-check current PR heads and workflow results before relying on historical status.
- Prior read-only verification reported that connected Supabase `public.hr_employees` lacked `archived_at` and `archived_by`, while the HR page selected `archived_at`. The remote migration ledger also lacked `20261015080000_add_hr_payroll_record_management`. Capture the current PostgREST response and reconcile the migration ledger through the authorized deployment process; do not manually mutate the live database as part of a repair.
- A prior clean-replay failure in `20260930013529_remove_abandoned_clinical_facility_reconciliation.sql` came from an unconditional `REVOKE` targeting a function absent at that point in replay. Verify later replay results instead of assuming that repair resolved the whole chain.
- Historical notes about duplicate migration versions are warnings to re-verify, not proof of current state. Never renumber applied migrations blindly.

## 10. Required completion report

For non-trivial fixes, report root cause/severity, files and database objects changed, migration/security implications, tests and commands actually run, commit SHA and PR/branch, latest CI statuses and the exact commit each run tested, remaining risks, blocked/unverified checks, and next action. “Fixed” means the root cause was corrected and relevant verification passed—not merely that code was edited.
