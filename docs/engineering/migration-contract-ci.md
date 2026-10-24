# Migration contract: clean and legacy schema coverage

The migration contract CI workflow replays the repository migration chain against a fresh local Supabase database, then executes a live pgTAP contract. The compatibility contract checks that the canonical laboratory reconciliation migration uses idempotent table, column, and function operations for the supported partially provisioned laboratory schema.

The compatibility checks intentionally do not fabricate patient, billing, or attachment rows and do not bypass RLS to make a fixture pass. A legacy fixture with ambiguous attachment URLs or mismatched patient/facility lineage must fail closed and be repaired through an explicitly reviewed data migration before deployment.

For each new migration family, add required tables, columns, indexes, RPC signatures and expected return types to the migration contract script, add catalog assertions to the SQL contract, and add clean/legacy fixture cases before relying on it in production.
