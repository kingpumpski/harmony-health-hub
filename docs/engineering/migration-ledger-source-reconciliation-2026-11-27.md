# Hosted migration ledger to repository source reconciliation — 2026-11-27

## Snapshot

Read-only comparison of the saved 417-entry hosted ledger baseline for project `ygqoptvezotdqhtimdkr` against the active repository `supabase/migrations` directory at commit `18b3aa660627347895373d6436f074255f0ff174`.

| Measure | Count |
|---|---:|
| Active repository migration files | 665 |
| Hosted ledger entries | 417 |
| Exact version + name source filename present | 68 |
| Version present but filename name differs | 10 |
| Hosted ledger versions absent from active directory | 339 |
| Absent versions with same-name file under another version | 182 |
| Absent versions with no same-name candidate | 157 |
| Duplicate local version groups | 21 (44 files) |

The machine-readable per-entry inventory is `migration-ledger-source-reconciliation-2026-11-27.json`. It records the exact Git blob SHA for each same-version file and same-name candidate. A CI contract verifies the snapshot against the active directory and saved ledger.

## Interpretation

The 417 hosted migration identities are internally consistent with the saved ledger baseline, but that does **not** mean the 417 original SQL bodies are present in the active repository.

- Only 68 ledger entries have an active SQL filename matching both the exact hosted version and name.
- Ten ledger versions exist locally but their filename suffix differs from the recorded hosted name.
- 339 hosted versions have no active file with that version. Of these, 182 have a file with the same name under another version; this is a candidate mapping only, not proof of byte-identical SQL or historical deployment.
- 157 hosted entries have neither an exact version file nor a same-name file candidate in the active migration directory.
- The ledger stores version/name identities only. It contains no SQL body or checksum, so it cannot prove that a same-name candidate is the original applied source.

This is a broader migration-provenance blocker than duplicate filenames alone. A clean replay of the 665-file directory cannot be treated as a replay of the 417-entry hosted history. The missing `20260916002251_canonical_remote_schema.sql` remains the most important baseline gap.

## Required resolution

1. Preserve this inventory and all source files; do not bulk-rename candidates to match ledger versions.
2. Recover original SQL from Git history, archived project exports, prior development environment backups, release artifacts, or backups where provenance can be verified.
3. For each same-name candidate, compare full SQL semantics and exact object effects against trusted release artifacts or database catalog evidence. A filename match is not enough.
4. Recover a complete schema-only export from the approved authoritative database as a separate new-environment bootstrap, with checksums and a clear exclusion policy for patient data, Auth users, storage objects, secrets and credentials.
5. Validate existing-environment upgrades independently from new-environment bootstrap. Do not fabricate historical SQL, backdate a baseline, or edit the hosted migration ledger to force parity.
6. Keep clean replay blocked until the historical source gap, the duplicate groups, and the canonical bootstrap path have explicit dispositions and disposable PostgreSQL 17 validation.

## CI contract

`scripts/migration-ledger-source-reconciliation-contract.mjs` verifies every ledger entry, local source status, candidate path and Git blob SHA against the captured inventory. It intentionally does not promote candidate files to authoritative migration sources or mark the migration history resolved.

No database writes, migration application, reset, or branch creation occurred during this audit.
