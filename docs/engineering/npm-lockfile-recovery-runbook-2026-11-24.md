# npm lockfile recovery runbook — 2026-11-24

## Evidence

At PR #444 head `42c28be79ebf0e24cf3214bbd98fa6de24688190`, Quality run #8901 and Migration contract run #2820 both fail at dependency installation.

The npm diagnostic explicitly reports missing lockfile records for:

- `@esbuild/win32-arm64@0.27.7`
- `@esbuild/win32-ia32@0.27.7`
- `@esbuild/win32-x64@0.27.7`
- `fast-uri@3.1.9`
- `json-schema-traverse@1.0.0`
- `require-from-string@2.0.2`

The same failure occurs in both workflows, so it is a shared lockfile graph defect rather than a workflow-specific install option. Root dependency declarations match between `package.json` and the lockfile root package record.

## Safe recovery workflow

A manual-only GitHub Actions workflow, `.github/workflows/recover-npm-lockfile.yml`, was added. It:

1. Checks out the migration reconciliation branch.
2. Uses the same Node major version (24) as project CI.
3. Records Node and npm versions.
4. Runs `npm install --package-lock-only --ignore-scripts` to regenerate the lock graph without executing package lifecycle scripts.
5. Runs a clean `npm ci --ignore-scripts` to validate lockfile/install consistency.
6. Uploads the resulting `package-lock.json` as a seven-day artifact for review.

The workflow has read-only repository permissions and does not commit or push the generated lockfile. It is triggered manually from GitHub Actions so the generated dependency graph can be inspected before any repository change.

## Acceptance criteria

- The manual workflow completes successfully.
- The artifact lockfile is downloaded and reviewed as a complete diff against the current lockfile.
- No unrelated direct dependency upgrades or package manifest edits are introduced.
- The candidate lockfile is committed to the reconciliation branch.
- Both normal CI workflows pass `npm ci` using the committed lockfile.
- Full application checks still run; this recovery workflow alone does not establish build, lint, typecheck, or runtime correctness.

## Separate migration failure

The migration contract clean-replay job still fails independently on the 21 duplicate migration version groups. This lockfile workflow does not suppress or alter migration validation and does not touch any Supabase project.
