# Migration governance and forward-only correction policy

## Authoritative history

- `main` is the integration baseline for the migration chain. A feature branch is not an independent migration authority.
- The ordered SQL files in `supabase/migrations` are the repository's source-controlled migration history. The Supabase migration ledger is the database's record of what has been applied. Both must be reconciled; neither can safely be inferred from the other.
- A migration version is the 14-digit timestamp prefix. New migrations must sort strictly after the highest version on the target baseline.
- A migration already present on the target baseline is immutable: do not edit, rename, delete, or reuse its version. This policy applies even when a previous migration is inconvenient or appears incorrect.

## Correcting defects safely

1. Identify the exact target branch and database environment. Capture the repository migration inventory and a read-only snapshot of the database migration ledger.
2. Compare version, migration name, and (where available) SQL checksum. Report local-only, database-only, and name-mismatch entries separately. A name/version match alone does not prove schema parity.
3. Determine whether the disputed migration has been applied to any shared environment. If yes or unknown, preserve its identity and contents; create a new timestamped forward correction.
4. Make the correction idempotent where appropriate, scoped to the intended schema and facility/tenant boundary, and safe for existing data. Avoid destructive data rewrites without an explicit backup, rollback/forward-recovery plan, and review.
5. Test the full chain from an empty database with `supabase db reset`, then run all database contracts. Separately validate an upgrade from a representative prior schema when the correction changes existing data or constraints.
6. Verify the linked non-production database's ledger and schema before production. Production application remains an explicit, serialized operation with a dry-run and operator confirmation.

## Branch and release rules

- Open migration changes as pull requests against `main`; rebase/reconcile before integration rather than merging unrelated branch histories wholesale.
- CI rejects edits, deletions, renames, duplicate versions, and newly introduced versions that do not sort after the target baseline.
- Resolve every migration conflict by retaining applied identities and adding a new forward migration. Never fix a conflict by renumbering a migration that may have been applied.
- A clean replay proves that the repository chain can build a fresh database; it does not prove that an existing hosted database has no drift. Both replay and live-ledger/schema verification are required.
- Never apply a proposed correction to production solely because it passes static checks.

## Required parity report

For each environment, record: branch and commit SHA; migration filename/version/name; database ledger version/name; checksum where obtainable; missing/extra entries; schema objects and constraints; grants, RLS policies and function privileges; clean replay result; upgrade-path result; application compatibility; and approval/deployment status.

Use explicit states: `MATCH`, `MISMATCH`, `UNVERIFIED`, or `BLOCKED`. Do not report parity as complete when the live database ledger or local working tree was not inspected.
