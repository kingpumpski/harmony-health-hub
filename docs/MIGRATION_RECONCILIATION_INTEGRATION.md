# Migration reconciliation integration

## Branch and safety boundary

This work is isolated on `integration/migration-reconciliation`, based on `main`. The existing `main` and `fix/missing-ai-diagnosis-schema-migration` branches are preserved. This branch is not permission to merge or apply migrations.

## Current production baseline

The baseline remains `unreconciled`. The original SQL for production versions `20260916002251` and `20260916003113` has not been recovered. Production apply is prohibited. Candidate provenance is not verified provenance.

## Changes in this integration tranche

- Make an unresolved baseline a failing validation result (exit code 2), rather than a green workflow with a warning.
- Keep production apply fail-closed (exit code 1).
- Add runtime tests for unresolved baseline, read-only verify, exact allowlist, unexpected versions, ambiguous rows, duplicate versions, and malformed allowlist entries.
- Remove the production `db push --dry-run` validation path while baseline provenance is unresolved.
- Require an exact, reviewed pending-version allowlist before any production apply step.

## Still required before declaring migration repair complete

1. Recover or independently establish authoritative evidence for the two canonical baseline entries; do not fabricate SQL.
2. Produce a per-version mapping of production ledger to repository migrations using Git history and SQL identity, including renamed files and collisions.
3. Review all 97 changed migration files and every rename/version change against deployment history.
4. Resolve SQL/function signature compatibility with actual application callers; do not change RPC return types merely to repair quoting.
5. Run delimiter, filename, dependency, and schema-contract checks.
6. Run clean replay and supported upgrade replay against a disposable local database after the Docker/Supabase local runtime is operational.
7. Run application lint, typecheck, full tests, build, and relevant GitHub Actions for the exact integration commit.
8. Obtain explicit review and approval before changing baseline status or production apply permissions.

## Prohibited actions

No production `supabase db push`, no direct edits to `supabase_migrations.schema_migrations`, no `supabase migration repair`, no fabricated baseline migrations, no `supabase db reset` against production, and no merge to `main` without explicit approval and passing required checks.

## Defects exposed by CI and repairs added to this branch

The first CI pass found three independent classes of problems:

- The clean local Supabase startup stopped at `20260910215228_81137334-9a88-408e-b7f3-0993eb7b9918.sql` because `public.ai_diagnosis_suggestions` had not been created before RLS was enabled. This branch adds the missing timestamped prerequisite migrations for reference tables, symptom-to-ICD mapping, and AI diagnosis suggestions, and makes the RLS migration idempotently restore the expected relations/policies.
- The delimiter scan exposed malformed bare-dollar delimiters in the Patient Hub entrypoints, clinical diagnosis context hardening, and inpatient admission workflow. The corresponding SQL files now use matching tagged delimiters.
- The fix-branch version of the insurance financial migration changed the function return type to JSONB. This branch explicitly preserves the main branch's composite `public.insurance_claims` return type and changes only the delimiter.

The initial quality run passed the baseline-gate runtime test, then failed on the delimiter checker and skipped subsequent checks as expected after the failure. The initial migration replay did not reach the full chain: local Supabase startup failed on the missing AI diagnosis prerequisite. The repairs above are committed for the next CI run; they are not yet verified by a completed rerun.

These edits are integration candidates only until production migration history confirms whether the added historical versions are already recorded. Do not push them to production while the baseline is unreconciled.

- The second clean-replay attempt advanced past AI diagnosis and failed in `20260911233000_phase2_service_order_payment_gating.sql`: the pre-existing `department_queues` table from the May schema lacked `queued_at` (and the later phase expected `service_order_id`, `claimed_by`, and `claimed_at`). Its `CREATE TABLE IF NOT EXISTS` declaration did not alter the legacy table. This branch now adds and backfills those columns before the index and RPC definitions, while retaining the later compatibility migration.

- The next replay reached `20260912002000_phase5_patient_audit_retention.sql` and failed because the expected legacy relation `public.patient_audit_log` was absent. The fix-branch compatibility version is now applied to this integration branch: it guards both `patient_audit_log` and the canonical `patient_audit` table, and safely does nothing when neither exists. The static migration contract already asserts these guards.

- Static migration contract testing then found duplicate version `20260912003000` assigned to both `phase2_pharmacy_procedure_imaging_gates` and `phase4_triage`. The integration candidate now moves the triage file to `20260912003500`, matching the fix branch's content-identical rename. This resolves repository version uniqueness for replay, but it is a **production-history risk** until the remote ledger proves which migration was recorded under `20260912003000`. Do not apply this rename to production or merge it until that mapping is independently confirmed.

- The static contract then found a second duplicate migration version: `20260912010000` was assigned to both the Phase 6 anesthetic foundation and Phase 8 AI clinical provenance files. The AI provenance file is now moved to `20260912010001`, with content verified identical to the fix-branch rename. As with the Phase 4 triage rename, production ledger provenance must confirm which file was historically recorded as version `20260912010000` before merge/apply.
- The next replay exposed the bulk-import legacy schema collision: `20260912005000_phase7_bulk_import_hardening.sql` used `CREATE TABLE IF NOT EXISTS` then indexed `entity_type`, even though the May legacy table had `entity`, `filename`, and `inserted_rows`. The fix-branch compatibility block is now moved before index creation in the integration candidate. It maps preserved legacy values and derives source format only from a verifiable filename extension; unknown legacy values fail closed rather than being silently guessed.
