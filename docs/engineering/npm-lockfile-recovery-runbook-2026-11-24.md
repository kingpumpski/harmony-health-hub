# npm lockfile recovery runbook — 2026-11-24

## Current evidence

At PR #444 head `f4baec8ba839b49ceef389bd1eccd950cbf3087e`:

- Quality run #8902 failed at dependency installation before typecheck, lint, application contracts, or build could execute.
- Migration contract run #2821 passed the forward-only regression and immutability/order checks, then failed at `npm ci` in the schema/security job.
- The clean replay job independently stopped at migration identity preflight on the 21 duplicate timestamp groups. Supabase startup and replay were not run.
- The latest npm diagnostic includes missing lockfile records across transitive packages and all platform-specific Esbuild packages, including `@esbuild/win32-arm64@0.27.7`, `@esbuild/win32-ia32@0.27.7`, `@esbuild/win32-x64@0.27.7`, `fast-uri@3.1.9`, `json-schema-traverse@1.0.0`, and `require-from-string@2.0.2`.

The same npm failure occurs in both normal workflows. Do not bypass `npm ci`, disable lockfile enforcement, or perform indiscriminate package upgrades.

## Safe recovery workflow

The workflow `.github/workflows/recover-npm-lockfile.yml` has read-only repository permissions and supports both:

- `pull_request` to `main` when `package.json`, `package-lock.json`, or the recovery workflow changes; and
- `workflow_dispatch` as a manual fallback.

It checks out the reconciliation branch, uses Node 24, records the Node/npm versions, runs:

1. `npm install --package-lock-only --ignore-scripts --no-audit --no-fund`
2. `npm ci --ignore-scripts --no-audit --no-fund`

On success, it uploads the generated `package-lock.json` as a seven-day artifact. It does not commit or push the candidate. Lifecycle scripts are disabled during this recovery validation; passing it proves lockfile/install-graph consistency only, not application build/runtime correctness.

## Acceptance criteria

- The recovery workflow completes successfully.
- Download and inspect the full artifact diff against the tracked lockfile.
- Confirm no unrelated direct dependency or `package.json` changes are introduced.
- Commit the reviewed candidate to the reconciliation branch.
- Rerun both normal CI workflows and require `npm ci`, typecheck, lint, application contracts, and production build to complete.
- Keep the migration identity gate fail-closed until each duplicate historical migration is individually reconciled from provenance and all environment ledgers.

## Separate migration blocker

The migration contract workflow still fails closed on 21 duplicate migration version groups. The lockfile workflow does not alter migration validation, migration SQL, or any Supabase project. Clean database replay remains blocked until the historical identities are resolved and independently verified.


## Merge-result manifest mismatch found and corrected

The first successful artifact run (#1) checked out the PR branch directly. Its generated lockfile was byte-for-byte identical to the tracked lockfile (Git blob SHA `ecbb7acceb69899170b80687d4725ea71cae9e35`), so it was not a repair. That run passed `npm ci` because the branch manifest did not include `@lovable.dev/mcp-js`.

A comparison of `main`, the PR branch, and the PR merge ref showed that `main` and the merge result include `@lovable.dev/mcp-js: ^3.6.0`, while the PR branch manifest did not. The merge result therefore had one more direct dependency than its lockfile. The PR branch manifest has now been aligned with the existing `main` declaration; this does not introduce a dependency that is absent from the target branch.

The recovery workflow now also runs on pushes to the reconciliation branch (as well as pull requests and manual dispatch), so the new manifest/lockfile pair can be regenerated and validated together. Review the next artifact before committing any lockfile changes.
