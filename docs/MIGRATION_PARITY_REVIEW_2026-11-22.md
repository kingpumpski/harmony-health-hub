# Migration parity review — November 22, 2026

## Outcome

Partial repair only. Migration validation defects are corrected; migration identities, deployed schema parity, and the pre-existing preview compilation failures remain unresolved. No SQL, database records, generated types, application queries, permissions, or account roles were changed.

Starting branch: `main`, starting commit: `6bcb723169a2d92fe88cba013c918827bb9c737b`. The repair commit is the commit introducing this report; use `git log -1` to identify it after committing. Remote PR heads and current CI runs could not be inspected: this checkout has a private code-storage origin, no GitHub CLI, and no available GitHub token. No remote check result is asserted.

## Defect ledger

| Symptom | Root cause / evidence | Repair or blocker |
| --- | --- | --- |
| Migration uniqueness stops at the first conflict | 651 SQL files contain 21 conflicting version groups (44 files) | Validator now reports every group, preserving all historical identities. Renumbering is blocked until current deployed version/name/SQL provenance is established. |
| SQL is silently excluded from replay | `supabase/migrations/$(path)` is not a recognized migration filename | Validator now fails on unrecognized files and empty SQL. The stray SQL was not renamed or applied: it replaces a notification function that has later security-sensitive definitions. |
| Static migration checks can disappear without failing CI | Workflow referenced absent `scripts/migration-contract.mjs` behind an optional existence condition | Added the validator and made it mandatory in migration and quality jobs. |
| Runtime contracts can be skipped | Workflow referenced absent `migration_contract.sql` and conditionally ran only the payroll contract | Clean replay now runs the existing database SQL contract directory, including laboratory, operational, authorization, and RLS checks; required contract assets are checked before services start. |
| Production validation lacks installed project dependencies | Migration workflow invoked project tests without Node setup / `npm ci` | Added dependency setup before integrity/identity checks and preserved confirmation, serialization, security tests, and stable quality job identity. |
| Deployed ledger cannot be verified | Read-only legacy-ledger request and managed migration-history inspection both failed due unavailable database access | No ledger edits, historical renumbering, or schema mutations attempted. |
| Local clean replay cannot run | `supabase start` reports Docker and Podman are unavailable | Clean replay and legacy upgrade paths remain unverified. Conflicting identities must also be reconciled before a valid full replay. |
| Preview reports unknown tables/RPCs and other compilation errors | Initial pre-edit observability log already reported stale generated-schema failures; this request changes no `src/` files | No fabricated schema adapter, generated-type rewrite, or type-check suppression added. Verified live schema/type refresh and separate application corrections remain blocked/unfinished. |

## Changed files

- `scripts/migration-inventory.mjs`: read-only inventory, SHA-256 fingerprints, all collision/invalid-file diagnostics, and version/name ledger comparison.
- `scripts/migration-parity.mjs`: JSON audit command; absent, invalid, or inconsistent history fails rather than claiming verified parity. Matching identities explicitly do not prove SQL/schema/RLS parity.
- `scripts/migration-filename-uniqueness-contract.mjs`: reports all violations, including ignored SQL.
- `scripts/migration-contract.mjs`: required migration identities/assets and referenced-script checks.
- `scripts/migration-parity-regression.mjs`, `scripts/migration-contract-workflow-regression.mjs`: positive and negative validator regressions.
- `.github/workflows/migration-contract.yml`, `.github/workflows/supabase-migrations.yml`, `.github/workflows/quality.yml`: mandatory validation, complete existing SQL-test coverage, dependency setup.
- `package.json`, `roadmap.md`, this report.

Database objects changed: **none**. Security implications: existing authorization, grants, RLS, tenant isolation, superuser protection, and deployment confirmation remain unchanged. Validation now fails explicitly where contracts were previously skipped.

## Verification actually performed

Passed:

- `npm run test:migration-parity` — all conflicts, ignored/empty SQL, invalid/missing/duplicate ledger records, read-only comparisons, matching identities, and negative CLI exit behavior; mandatory workflow coverage.
- `npm run test:migration-workflow-safety`
- `npm run test:migration-workflow-concurrency`
- `npm run test:laboratory-attachments-schema`
- `npm run test:hr-payroll`
- `npm run test:project-integrity`
- `npm run test:edge-schema-role-inventory`
- `bunx eslint` for all six changed/added migration validator scripts.
- PyYAML parsing of all three changed workflows.
- `git diff --check`.

Failed with the actual unresolved defects (not suppressed):

- `npm run test:migration-contract` — 21 duplicate version groups and the unrecognized `$(path)` file.
- `npm run migration:parity` / `node scripts/migration-parity.mjs` — the same identity defects; no current live ledger is available. JSON inventory captured under `/tmp` during this task.
- `supabase start` — no Docker/Podman; no replay ran.
- Read-only deployed ledger and managed migration-history inspection — database unavailable.

Unverified: production schema/SQL identity, deployed grants/RLS, generated-type compatibility, clean replay, supported upgrade paths, full lint/application checks, authenticated clinical workflows, GitHub CI at the final commit, deployment, branch protection. Existing build errors remain present; no error-free preview is claimed. Builds/type-checks were not run manually in this environment.

## Safe next steps

1. Restore database read access and obtain current version/name/SQL histories for every supported deployment; the checked-in UTF-16 migration list is historical, has no SQL identities, and is not proof of current deployment state.
2. Run `npm run migration:parity -- --ledger /tmp/current-ledger.json` using an explicitly sourced current JSON array of `{ "version": "…", "name": "…" }`. This command is read-only; it does not resolve baseline mappings or certify live schema parity.
3. Establish each conflicting file's deployment identity and prerequisites before assigning any new version to a confirmed-unapplied operation. Preserve applied provenance and do not manufacture the documented remote baseline.
4. Reconcile the stray notification SQL against the latest canonical notification authorization function before deciding whether it represents an unapplied repair or an obsolete artifact.
5. Run clean replay and every existing SQL contract on disposable supported services, then deploy only verified forward repairs through the authorized managed workflow. Do not reset live data or push the historical chain blindly.
6. Verify actual schema, refresh generated types using the supported process, fix remaining application errors without suppressions, and test authenticated patient/lab/pharmacy/billing flows.
7. Inspect completed mandatory CI runs for the actual final commit before treating this work as merge/release ready.

The workspace ran out of credits before full reconciliation; continuing requires available credits as well as restored database access and local replay infrastructure.