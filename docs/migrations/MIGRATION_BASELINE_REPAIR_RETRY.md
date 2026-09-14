# Migration Baseline Repair Retry

This marker retries the canonical production migration baseline after removing the storage-schema dump that was unexpectedly creating a second remote migration-history record during the baseline workflow.

Production remains the schema authority. The workflow archives the executable migration chain, repairs migration-history tracking only, pulls a single canonical production baseline, validates lint, and commits the resulting baseline.