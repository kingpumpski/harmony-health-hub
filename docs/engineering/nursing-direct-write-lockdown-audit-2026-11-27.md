# Nursing lifecycle direct-write lockdown — 2026-11-27

## Decision

Stage a forward-only privilege correction for `nursing_shift_handovers` and `nursing_care_plans`. Authenticated clients retain SELECT, but direct INSERT/UPDATE/DELETE is removed. Anonymous and PUBLIC table privileges are removed. Lifecycle mutations remain on authenticated, facility-aware SECURITY DEFINER RPCs.

This is a repository change only. It has not been applied to the hosted database.

## Evidence: application caller inventory

- `src/pages/NursingHandover.tsx` creates handovers with `create_nursing_shift_handover` and acknowledges them with `acknowledge_nursing_handover`; it does not write the table directly.
- `src/pages/dashboard/NurseDashboard.tsx` obtains the dashboard through the `ai-clinical-assist` Edge Function and subscribes to handover changes; it does not mutate the handover table.
- `supabase/functions/ai-clinical-assist/index.ts` reads handovers for the nurse dashboard; it does not mutate them.
- `src/pages/ClinicalOperations.tsx` creates care plans through `create_nursing_care_plan`; no direct table mutation was found.
- Repository code search found no additional direct table mutation call sites for these two tables. The current UI does not call `review_nursing_care_plan`.

## Read-only hosted catalog evidence

Project `harmony-health-hub` was inspected read-only on 2026-11-27.

- `nursing_shift_handovers`: authenticated SELECT/INSERT/UPDATE/DELETE privileges were all present.
- `nursing_care_plans`: authenticated SELECT/UPDATE/DELETE were present; INSERT was absent.
- Both tables had RLS enabled. Their permissive role policies allow broad nursing/clinical role actions, while restrictive facility policies apply to SELECT only. These SELECT-only policies do not establish equivalent facility checks for direct write operations.
- The hosted catalog's effective table privileges conflict with the repository's older direct-write-lockdown source migration. The hosted migration ledger records the corresponding clinical hardening work under different timestamp/name identities, so source-file presence alone cannot explain the effective ACL state.
- Hosted `create_nursing_shift_handover`, `acknowledge_nursing_handover`, and `create_nursing_care_plan` are SECURITY DEFINER, have empty search paths, are executable by authenticated and not anon, and enforce facility context in their bodies. The handover acknowledgement also locks the row and prevents self-acknowledgement.
- No live `review_nursing_care_plan` function was returned by the catalog inspection.

RLS remains enabled; the observed grants are not proof that an unauthorized caller can read or mutate another facility's rows. They are nevertheless broader than the application's RPC-only write design and should be corrected.

## Forward repair

Migration: `supabase/migrations/20261127103000_lock_nursing_lifecycle_table_writes.sql`

- Revoke all table privileges from PUBLIC and anon.
- Revoke authenticated INSERT, UPDATE, and DELETE.
- Preserve authenticated SELECT, subject to existing RLS.
- Do not alter role policies, RPC definitions, table data, or facility semantics.

Static contract: `scripts/nursing-direct-write-lockdown-contract.mjs`.

Database security contract additions verify the effective grants and authenticated-only facility-aware RPC surface when the database suite can run.

## Validation and limits

- The source caller inventory supports RPC-only writes for the current application.
- The live catalog confirms the current RPC definitions and ACLs.
- The new migration and contracts are staged for review and CI only.
- No SQL was applied, no table data was changed, and no reset was performed.
- The migration workflow is still blocked before PostgreSQL startup by 21 duplicate migration-version groups. Therefore this repair has not been replayed against a disposable PostgreSQL instance and is not deployment-ready.

## Remaining nursing follow-up

1. Add an explicit care-plan review workflow only after its role/action and facility rules are approved; do not restore direct UPDATE/DELETE grants as a shortcut.
2. Verify whether any external integrations outside this repository depend on direct table writes before deployment.
3. After migration-history reconciliation, run positive and negative facility-context database tests for create/acknowledge RPCs and the resulting table grants.


## Generated type comparison and CI confirmation

A fresh read-only Supabase TypeScript type generation was compared with the repository's `src/integrations/supabase/types.ts` for six affected tables: `nursing_shift_handovers`, `nursing_care_plans`, `service_orders`, `emergency_cases`, `theatre_cases`, and `transfusion_records`. Their generated Row/Insert/Update and relationship blocks match the repository type blocks for these selected tables.

The generated live handover type does not contain `ward_id`, consistent with the live catalog omission. The separate forward migration `20261127100200_restore_nursing_handover_ward_link.sql` is staged but unapplied, so type regeneration for that relationship must wait until the migration is replayed and verified. The selected comparison is not a whole-schema type parity certification.

On commit `a242b824474fe63f686869bab7fd8e5e8cfa89fc`:
- Quality workflow [#46019159271](https://github.com/kingpumpski/harmony-health-hub/actions/runs/46019159271) passed (81 job steps, no failed steps).
- Migration contract workflow [#46019159301](https://github.com/kingpumpski/harmony-health-hub/actions/runs/46019159301) passed migration parity and the new nursing direct-write static contract, then failed at the historical migration identity preflight on the known 21 duplicate timestamp groups. PostgreSQL startup and replay were skipped.
