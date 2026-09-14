# Migration Baseline Repair Retry

This marker retries the canonical production migration baseline after reconciling schema contracts exposed by production lint.

Production remains the schema authority. The workflow archives the executable migration chain, repairs migration-history tracking only, pulls a single canonical production baseline, validates lint, and commits the resulting baseline.