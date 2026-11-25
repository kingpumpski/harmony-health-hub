# Migration collision review: 20260912021000

Updated: 2026-11-25

## Scope

Compared both migration candidates sharing version `20260912021000` with the live canonical PostgreSQL catalog. This is a read-only provenance, schema-evolution, and authorization review. No migration was selected, renamed, replayed, or applied.

Candidates:
- `20260912021000_attending_patient_history_summary.sql`
- `20260912021000_global_hims_operations.sql`

## Decision

**Both feature tracks are present in the live database, but neither original candidate is safe to replay unchanged.** The live implementation contains later facility-context hardening and schema evolution. Preserve both source files and resolve the version collision only after provenance review and disposable replay.

## A. Attending patient history RPC

The live database has `get_attending_patient_history(uuid,uuid)`. Compared with the candidate, the live implementation:
- Calls `assert_patient_facility_read_context(_patient_id)` before reading clinical history.
- Validates that a supplied current encounter belongs to the requested patient.
- Uses a pinned `pg_catalog, public` search path.
- Includes a broader privileged-role rule for the current deployment.

The candidate lacks both facility-context enforcement and current-encounter ownership validation. Replaying it could replace the safer live function body with a weaker authorization boundary. Its query also joins several clinical domains, so the facility check is essential even though the function is SECURITY DEFINER.

**Disposition:** retain the live hardened behavior; do not restore the candidate body verbatim. Any future changes must preserve patient facility-read context, encounter ownership, role checks, and safe search path. Test cross-facility denial and same-facility reads.

## B. Global HIMS operations foundation

The four candidate table families exist in the live schema:
- `facility_configuration`
- `system_audit_log`
- `maternity_episodes`
- `maternity_observations`

Live row counts at review time were 1, 945, 1, and 1 respectively. Live tables have evolved beyond the candidate, including facility attribution on maternity episodes and restrictive facility SELECT guards on maternity episodes.

### Important live authorization findings

1. **Maternity observations lack a facility boundary in the inspected RLS policies.** The live SELECT policy is a permissive clinical-role check; INSERT/UPDATE policies check the recording actor or admin role. No restrictive facility policy or facility-lineage trigger was present on `maternity_observations` in the inspected catalog. Because observations belong to maternity episodes, a clinical user with access to the table may be able to read or write observations attached to another facility's episode unless another database boundary prevents it. This requires an immediate focused access test and a forward-only repair. Do not assume the parent episode's RLS policy automatically filters child rows.

2. **System audit direct INSERT is too permissive for an authoritative audit ledger.** The live policy permits authenticated users to insert rows when `actor_id = auth.uid()`; it does not constrain action, module, entity, severity, or metadata. The SECURITY DEFINER `record_system_audit` RPC also accepts caller-supplied values and does not validate a fixed action vocabulary. The audit table has 945 rows and an operational row-change trigger is present on other operational tables. Direct client INSERT should be removed in a forward migration after verifying all legitimate writers use trusted RPCs/triggers. Audit records should not be user-forgeable.

3. **Facility configuration has authenticated read access to every row.** This matches the candidate's broad read policy but the table includes contact and operational settings. Confirm that every field is appropriate for all authenticated staff; split public operational configuration from admin-only secrets or internal settings if not.

4. Maternity episodes have facility-lineage enforcement on insert/update and restrictive facility SELECT guards. The live patient FK uses `ON DELETE CASCADE`; patient archive/retention rules must be settled before physical patient deletion is permitted.

5. `system_audit_log.actor_id` is nullable and uses `ON DELETE SET NULL`, which is internally consistent. The separate AI event actor FK conflict remains distinct.

### Candidate design hazards

- The candidate's maternity RLS is role-only and has no facility dimension. Do not reintroduce it without facility-safe policies and parent/child lineage checks.
- The candidate's system audit policy permits direct authenticated inserts. This is unsuitable for a tamper-resistant audit record.
- The candidate defines a singleton facility-configuration row via a unique expression index. Live configuration has evolved; preserve current semantics rather than recreating the candidate table.
- The candidate history function has no facility read assertion and does not validate the optional encounter relationship.

## Required actions

1. Add a focused disposable-session test proving whether a user at Facility A can SELECT, INSERT, UPDATE, or DELETE `maternity_observations` linked to a Facility B episode.
2. If confirmed, add a forward migration with parent-episode facility validation for every observation write and restrictive facility-aware read policies. Use existing facility helper contracts and test test-account boundaries.
3. Inventory every writer of `system_audit_log` (RPCs, triggers, edge functions, backend service roles) before revoking direct authenticated INSERT. Preserve trusted server-side and trigger writes; test actor attribution and immutable history.
4. Restrict or split `facility_configuration` reads based on field sensitivity.
5. Keep `get_attending_patient_history` facility checks and current-encounter ownership validation intact.
6. Reconcile both candidates' original commit provenance and all subsequent migrations before assigning a unique historical identity.
7. Validate both clean bootstrap and upgrade-from-hosted-baseline on disposable PostgreSQL 17/Supabase.

## Execution boundary

All inspection was read-only. No patient or maternity records were read beyond aggregate row counts and schema metadata. No SQL was applied, and no migration filename was changed. The collision remains unresolved.
