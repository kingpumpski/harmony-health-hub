# Production migration baseline repair

This marker intentionally triggers the repository's canonical migration-baseline workflow.

The production Supabase project is the schema authority. The baseline workflow will capture the live production schema, archive the divergent executable migration chain, repair migration-history tracking, and generate a reproducible canonical baseline without rolling back production schema or data.
