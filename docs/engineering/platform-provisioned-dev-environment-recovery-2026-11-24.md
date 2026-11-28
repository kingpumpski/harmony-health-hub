# Platform-provisioned development environment: recovery decision — 2026-11-24

## User clarification

The user confirmed that Supabase project `pmebpkcufyrbjhawsiyn` was the default development environment supplied by the platform when the project was first created. The user does not own or have access to that environment.

This is not an access grant problem to route back to the user. Do not ask the user to obtain membership or credentials for that platform-managed project, and do not represent it as a user-controlled development database.

## Revised disposition

- Treat `pmebpkcufyrbjhawsiyn` as a legacy/platform-provisioned development target whose database state is currently inaccessible.
- Do not attempt to alter it, rotate its secrets, deploy functions to it, or infer its schema from its URL/project ID.
- Continue development from version-controlled source and the accessible canonical Supabase project `ygqoptvezotdqhtimdkr`, keeping their roles separate.
- Establish a reproducible, project-controlled development environment only after the repository's migration history and authoritative schema are reconciled. The new environment must be created from reviewed source, not from fabricated historical migrations.
- Preserve the existing production/canonical database. Do not reset it or use it as a disposable development target.
- If the platform later provides an export or a recoverable snapshot of the default environment, compare it read-only against the reviewed schema; it is not a prerequisite for ongoing repository work.

## Recovery sequence

1. Repair the repository CI dependency installation so static checks can run.
2. Reconcile the 21 duplicate migration versions using per-file provenance and dependency analysis; do not bulk rename or delete.
3. Recover the exact historical baseline/source if available. If it cannot be recovered, build a separately versioned, reviewed fresh-environment bootstrap from a complete authoritative schema export. Never impersonate the missing historical baseline.
4. Validate the bootstrap on a disposable PostgreSQL/Supabase instance, including grants, RLS, functions, triggers, extensions, and application RPC contracts.
5. Provision a new project-controlled development Supabase project and apply only the verified bootstrap/forward migrations there.
6. Point the development build to that project's URL and matching publishable key. Keep service-role credentials server-side only.
7. Re-test the browser errors against the new controlled environment. Treat errors specific to the inaccessible platform environment as legacy environment drift unless they reproduce.

## CI evidence at commit `8cd1a5bb16c9a1646ae9b000f688339435e5cfc4`

Quality run #8900 and Migration contract run #2819 both failed at `npm ci`.

The Quality log reports npm `EUSAGE`: numerous packages are missing from the lockfile and several locked versions do not satisfy the package tree npm is resolving. The `package.json` root dependency declarations and lockfile root declarations match, so the defect is in the resolved lockfile graph, not a simple missing top-level dependency. The migration clean-replay job separately fails at its migration identity preflight on the 21 duplicate version groups; database startup and replay are skipped.

The correct dependency fix is to regenerate the lockfile using the repository's intended Node 24/npm toolchain, inspect the complete dependency graph diff, and prove `npm ci` succeeds from a clean checkout. Do not weaken `npm ci`, bypass lockfile enforcement, or run indiscriminate package upgrades.

## Safety status

No Supabase project was modified. No migrations were applied. No credentials were requested or exposed. PR #444 remains draft and unmerged.
