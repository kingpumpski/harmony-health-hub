# Laboratory panel privilege and trigger hardening — 2026-11-27

## Live read-only findings

Project `ygqoptvezotdqhtimdkr` was inspected read-only.

- `lab_test_groups` and `lab_test_group_items` both have RLS enabled, but neither table has an RLS policy.
- Despite the policy-less RLS boundary, effective table ACLs currently grant SELECT, INSERT, UPDATE and DELETE to both `anon` and `authenticated`. RLS with no applicable policies denies row access, but broad grants are unnecessary and do not match the intended design.
- The current application component `src/components/laboratory/LabTestGroupsManager.tsx` reads and writes exclusively through `get_laboratory_test_groups` and `save_laboratory_test_group`; no direct PostgREST table mutation is used.
- Both live RPCs are SECURITY DEFINER, use an empty search_path, grant EXECUTE to authenticated, and do not grant EXECUTE to anon. The read RPC scopes results to the active facility and restricts inactive-panel access; the save RPC requires an active facility and authorized administration roles.
- The live `public.ensure_updated_at()` trigger function is SECURITY INVOKER, owned by postgres, has no function-level search_path configuration, and is attached to update triggers on `lab_test_groups`, `lab_test_group_items`, and `lab_orders`. Its body only assigns `NEW.updated_at := now()`, so pinning an empty path is a narrow, semantics-preserving hardening change.
- These findings match the intent of the existing staged migration `20261127100100_harden_laboratory_panel_table_privileges_and_timestamp_trigger.sql`, which revokes all direct privileges from PUBLIC, anon and authenticated on the two panel tables and pins `ensure_updated_at()` to an empty search_path.

## Regression coverage added

Added `supabase/tests/database/laboratory_panel_access_contract.sql` to verify:
1. No direct table ACL grants remain for PUBLIC, anon or authenticated on either panel table.
2. RLS remains enabled on both panel tables.
3. The two panel RPCs remain authenticated-only SECURITY DEFINER functions with an empty search_path.

Existing source contracts already cover the staged privilege migration and the `ensure_updated_at` search_path configuration. The migration workflow executes the database SQL contracts after a clean replay.

## Deployment status and limitations

The migration is repository-only and has not been applied to the hosted database. Live grants and the mutable search_path finding therefore remain present until a reviewed migration release is applied. The migration-history preflight still blocks PostgreSQL replay because of the 21 duplicate migration-version groups. No database writes, resets, data changes or branch creation were performed.


## CI checkpoint

On commit `7d326241d98315e625edc2deffa2ad375c403d27`:
- Quality workflow [#46022136691](https://github.com/kingpumpski/harmony-health-hub/actions/runs/46022136691) passed.
- Migration contract workflow [#46022136687](https://github.com/kingpumpski/harmony-health-hub/actions/runs/46022136687) ran the migration-parity source contracts successfully, including the existing laboratory privilege contract and the new nursing direct-write contract. It then failed closed at `npm run test:migration-contract` because the migration inventory still contains the 21 historical duplicate timestamp groups. The database replay job failed the same duplicate-identity preflight; Supabase startup and SQL replay were skipped.
- The new database ACL contract is registered as a required contract asset. It has not yet executed against PostgreSQL because clean replay is blocked.
