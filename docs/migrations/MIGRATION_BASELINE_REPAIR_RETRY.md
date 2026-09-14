# Migration Baseline Repair Retry

This marker retries the canonical production migration baseline after removing the storage-schema dump that was unexpectedly creating additional remote migration-history records during the baseline workflow.

The retry also regenerates `src/integrations/supabase/types.ts` directly from the canonical production public schema so the application contract is reconciled with the same schema baseline.

Production remains the schema authority. The workflow archives the executable migration chain, repairs migration-history tracking only, pulls a single canonical production baseline, validates lint, regenerates the database TypeScript contract, and commits the resulting baseline.