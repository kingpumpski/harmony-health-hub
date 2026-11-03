# Production migration provenance candidate report

Snapshot date: 2026-11-02  
Repository commit: `31645d93d07fd620c3e7c54df9907ce239b3ebaf`  
Supabase project: `ygqoptvezotdqhtimdkr`

The machine-readable candidate inventory is `docs/PRODUCTION_MIGRATION_PROVENANCE_CANDIDATES.json`.

## Snapshot counts

| Measure | Count |
|---|---:|
| Repository SQL migration files | 661 |
| Remote migration ledger entries | 417 |
| Exact version matches | 80 |
| Remote-only versions | 337 |
| Local-only versions | 581 |
| Remote-only entries with one same-name local candidate | 257 |
| Remote-only entries with multiple same-name candidates | 1 |
| Remote-only entries with no same-name candidate | 79 |

## Interpretation

- An exact version match proves that the local filename version appears in the remote ledger. It does not prove the SQL content is unchanged or that the current live schema still matches that migration's intended effect.
- A same-name candidate is only a search lead. It does not establish that the remote migration ran the same SQL.
- The one ambiguous same-name case must be resolved using Git history, content hashes, dependency order, and schema evidence.
- Entries with no local candidate require historical recovery or explicit documentation of why the production-only migration has no repository source.
- Local-only entries must not be automatically pushed. Some may be old source migrations already represented by the canonical production baseline or later reconciliations.

The JSON records Git blob SHAs for the local files as provenance identifiers. These are Git object hashes, not SHA-256 content digests. The generator `npm run migration:register` separately computes SHA-256 hashes for the current repository migration files.

## Safety decision

This report is candidate-only. It does not authorize `supabase migration repair`, direct edits to `supabase_migrations.schema_migrations`, or production `supabase db push`. Production remains blocked by `supabase/production-migration-baseline.json` until every relevant mapping is reviewed and an exact pending-version allowlist is approved.
