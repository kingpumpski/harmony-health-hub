# Migration History Baseline

This archive was created from the production Supabase project before repairing migration history.

## Pre-repair remote history
```text

  
   Local | Remote           | Time (UTC)            
  -------|------------------|-----------------------
   ` `   | `20260913234500` | `2026-09-13 23:45:00` 
   ` `   | `20260913234959` | `2026-09-13 23:49:59` 

```

## Post-repair remote history
```text

  
   Local            | Remote           | Time (UTC)            
  ------------------|------------------|-----------------------
   `20260913235155` | `20260913235155` | `2026-09-13 23:51:55` 

```

The archived migrations remain available under `supabase/migrations-archive/` for audit/reference but are no longer part of the executable migration chain.
