# Migration replay baseline gap

**Assessment date:** 2026-11-23  
**Repository:** `kingpumpski/harmony-health-hub`  
**Branch:** `chore/forward-only-migration-governance`  
**Supabase project:** `ygqoptvezotdqhtimdkr`

## Verified findings

1. The captured live Supabase migration ledger contains **417** entries. Its earliest entry is version `20260916002251`, named `canonical_remote_schema`; its latest entry is `20261026141054`.
2. The repository's captured ledger baseline records that same first entry.
3. The active migration path `supabase/migrations/20260916002251_canonical_remote_schema.sql` does **not** exist on the reconciliation branch (GitHub contents API returned not found).
4. The active migration inventory still contains 21 duplicate version groups, all of which fail the preflight contract. The most recent migration workflow (#2803) stopped at this preflight; local Supabase startup, clean replay, and post-replay schema verification were skipped.
5. The linked project ledger is not a SQL source archive: it records version/name identities, not the original SQL payloads or checksums.

## Why this matters

The missing `canonical_remote_schema` source is a separate replay-readiness gap from the 21 duplicate filenames. Even if the duplicate groups were resolved, a clean database replay cannot be considered reproducible merely because the live ledger says a migration with this name was applied. The repository currently has no corresponding active SQL file to establish what schema state that baseline created.

The first hosted ledger entry may represent a schema baseline captured after the original pre-Supabase development period. That is a plausible interpretation, not a verified fact. The known legacy development environment predates Supabase, and its schema snapshot/history has not been supplied.

## Safe resolution requirements

1. Recover the original `canonical_remote_schema` SQL or an authoritative schema-only dump from the exact point represented by ledger version `20260916002251`. Acceptable provenance would include a verified backup/export, deployment artifact, or original Git commit—not a fresh dump of today's production schema.
2. Verify the recovered artifact against the schema state expected immediately after that baseline, using available historical backups, migration records, and object-level comparisons.
3. Resolve the 21 duplicate version groups without deleting distinct SQL or guessing which file ran. Establish a canonical pre-baseline history or a separately documented bootstrap strategy with a clean, isolated replay.
4. Recover the three missing late-October hosted migration sources and verify the two recovered candidates' provenance.
5. Only then run a clean replay in an isolated local database and compare tables, columns, constraints, indexes, policies, triggers, functions, grants, and required seed/reference data with the intended schema.
6. Keep production migration apply disabled until the replay and schema comparison pass.

## Explicitly not authorized by this assessment

- Do not use a current production schema dump as though it were the September 16 baseline; it would already include later migrations and could make replay results misleading.
- Do not insert a placeholder or empty migration named `canonical_remote_schema`.
- Do not mark historical migrations as applied merely to bypass replay.
- Do not renumber, delete, combine, or rewrite the 21 collision groups without source provenance and a verified replay plan.
- Do not apply any historical or staged migration to production as part of this investigation.

## Current disposition

PR #444 remains draft. The application Quality workflow passed on the latest tested head, but the migration contract remains blocked by the 21 duplicate version groups. The missing baseline SQL source is an additional, independently verified gap that must be resolved before clean replay can establish migration integrity. No production DDL or migration-ledger changes were made.
