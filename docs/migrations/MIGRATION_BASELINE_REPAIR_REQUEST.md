# Migration Baseline Repair Request

This marker intentionally triggers the canonical production migration baseline workflow.

Production remains the schema authority. The baseline workflow archives the divergent repository migration chain, clears migration-history tracking records without rolling back production schema, pulls the current production schema into one canonical migration, captures storage policy state without creating a second migration-history record, validates the resulting schema, and commits the repaired baseline.

This is a migration-history repair operation only; it does not request destructive data changes or a production schema rollback.
