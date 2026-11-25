# Migration collision review: 20260912021000

Updated: 2026-11-25

## Scope

Compared both migration candidates sharing version `20260912021000` with the live canonical PostgreSQL catalog and inspected later hardening migrations. This is a read-only provenance, schema-evolution, and authorization review. No migration was selected, renamed, replayed, or applied.

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

1. **High-priority: maternity workspace SECURITY DEFINER RPC has no facility read assertion.** The live `get_maternity_workspace(integer,uuid)` is SECURITY DEFINER, executable by authenticated users, and checks clinical role membership. Its query joins maternity episodes to patients but does not call `assert_patient_facility_read_context`, constrain the result to the active facility, or apply a privileged-role policy. It can aggregate episodes across facilities for any caller who passes the role check. Because SECURITY DEFINER bypasses ordinary table RLS, the restrictive facility SELECT policy on `maternity_episodes` does not protect this RPC. This is a confirmed authorization gap in the inspected function definition and should be treated as a priority forward repair.

2. **High-priority: maternity observations have no independent facility read policy.** The live `maternity_observations` SELECT policy is a permissive clinical-role check; no restrictive facility policy or facility-lineage trigger was present on that table in the inspected catalog. Authenticated users have SELECT privilege. The parent episode's RLS does not automatically filter child-table queries. The SECURITY DEFINER maternity workspace compounds this issue because it returns observations without a facility assertion. Direct authenticated INSERT/UPDATE/DELETE privileges are revoked, and the write RPC `record_maternity_observation_workflow` does call `assert_patient_facility_context` and compare active facility for ordinary staff. Therefore, the confirmed concern is cross-facility reads through direct SELECT and the workspace RPC; do not characterize direct client writes as enabled.

3. **System audit direct table mutation is already hardened in the live database.** A later migration, `20260914161000_audit_log_direct_mutation_hardening.sql`, revokes authenticated INSERT/UPDATE/DELETE on `system_audit_log` and `audit_logs`. The live privilege check confirms authenticated users have no INSERT/UPDATE/DELETE table privileges. The earlier candidate's permissive INSERT policy is therefore superseded by later privilege hardening; do not propose repeating that revocation as a new fix. Residual review item: authenticated callers can execute `record_system_audit`, which accepts caller-supplied action, module, severity, entity and metadata. Review whether the RPC should enforce an event vocabulary or be limited to trusted server-side call paths. Preserve trigger-based audit writers.

4. **Facility configuration has authenticated read access to every row.** The live table has one row and authenticated SELECT. This matches the candidate's broad read policy but the table includes contact and operational settings. Confirm that every field is appropriate for all authenticated staff; split public operational configuration from admin-only secrets or internal settings if not.

5. Maternity episodes have facility-lineage enforcement on insert/update and restrictive facility SELECT guards. The live patient FK uses `ON DELETE CASCADE`; patient archive/retention rules must be settled before physical patient deletion is permitted.

6. `system_audit_log.actor_id` is nullable and uses `ON DELETE SET NULL`, which is internally consistent. The separate AI event actor FK conflict remains distinct.

### Candidate design hazards

- The candidate's maternity RLS is role-only and has no facility dimension. Do not reintroduce it without facility-safe policies and parent/child lineage checks.
- The candidate's system audit policy permits direct authenticated inserts, but this has been superseded by the later table-privilege hardening migration.
- The candidate defines a singleton facility-configuration row via a unique expression index. Live configuration has evolved; preserve current semantics rather than recreating the candidate table.
- The candidate history function has no facility read assertion and does not validate the optional encounter relationship.

## Required actions

1. Forward-repair `get_maternity_workspace` so every returned episode and observation is facility-scoped. For a selected episode, call `assert_patient_facility_read_context` on its patient before returning any details. For list mode, filter through the caller's active facility and explicitly define privileged-role and test-account behavior; do not return a cross-facility aggregate to ordinary staff.
2. Add restrictive facility-aware SELECT protection to `maternity_observations`, using its parent episode and patient facility lineage. Preserve the current write RPC's patient-context assertion and active-facility comparison.
3. Add regression tests for Facility A versus Facility B, including list mode, selected-episode mode, direct child-table SELECT, privileged access, and test-account isolation.
4. Review `record_system_audit` caller-supplied event fields and restrict the function to trusted audited paths if necessary. Do not remove existing trigger-based writers or the already-applied direct-DML revocation.
5. Restrict or split `facility_configuration` reads based on field sensitivity.
6. Keep `get_attending_patient_history` facility checks and current-encounter ownership validation intact.
7. Reconcile both candidates' original commit provenance and all subsequent migrations before assigning a unique historical identity.
8. Validate both clean bootstrap and upgrade-from-hosted-baseline on disposable PostgreSQL 17/Supabase.

## Execution boundary

All inspection was read-only. No patient or maternity records were read beyond aggregate row counts and schema metadata. No SQL was applied, and no migration filename was changed. The collision remains unresolved.


## Follow-up catalog recheck (2026-11-25 13:30 UTC)

A focused read-only recheck refined the ACL and audit findings:

- `maternity_observations` still has no `facility_id`, no facility-lineage trigger, and only role-based SELECT/INSERT/UPDATE/DELETE policies. Its only observed trigger is the operational row-change audit trigger. Authenticated table grants observed are SELECT only; authenticated direct DML was not present in the effective grant listing. The immediate risk is therefore the role-only child-table read policy and any privileged RPC that returns these rows, not a claim that authenticated direct DML is enabled.
- `maternity_episodes` retains its facility-lineage trigger and two facility-aware SELECT policies. Its older clinical role policies coexist with those policies; review the combined permissive/restrictive policy semantics rather than assuming a single policy defines access.
- `get_attending_patient_history(uuid,uuid)` remains SECURITY DEFINER, authenticated/service_role executable, anon denied, and calls `assert_patient_facility_read_context` plus current-encounter ownership validation. Its live `pg_catalog, public` path is intentional observed state for this function; do not replace it with the older candidate definition.
- `record_system_audit(text,text,text,uuid,text,jsonb)` remains SECURITY DEFINER, anon denied, authenticated/service_role executable, and checks authentication only before accepting caller-provided action, module, entity, severity, and metadata. The live `system_audit_log` policy still describes actor-attributed INSERT, but the effective authenticated table grants observed do not include INSERT/UPDATE/DELETE. Preserve the later direct-DML revocation; focus the residual review on whether the generic RPC is too permissive for an authoritative audit stream.
- `facility_configuration` has authenticated SELECT with `USING (true)` and admin-only write policies. Anon has broad table-level grants in the role-grant listing, but no anon policy was observed; that is not evidence of anon row visibility. The table has no `facility_id` and is singleton-shaped, so changing it to per-facility configuration requires a separate product/data migration decision.
- Maternity episodes and observations both have an `audit_operational_row_change` trigger. Only maternity episodes have the observed facility-lineage trigger.

No maternity, patient, audit, or configuration row contents were queried during this recheck. No database writes or deployments occurred.


## Maternity workspace SECURITY DEFINER follow-up (2026-11-25)

A focused function-body inspection identifies a more direct exposure path than the child-table RLS policy alone:

- `get_maternity_workspace(integer,uuid)` is SECURITY DEFINER with an empty search_path, but it does not call `current_user_facility_id()` or a patient-facility assertion.
- Its episode query joins maternity episodes to patients but does not filter either record by the caller's active facility.
- Its observation query joins observations to episodes and patients but likewise does not constrain the episode/patient facility to the caller.
- For a supplied `_episode_id`, the existence check only verifies that the episode joins to a patient; it does not establish caller facility access.
- The function returns episode and observation data in JSON, so underlying table RLS does not protect these owner-executed queries.

The separate `record_maternity_observation_workflow` is materially stronger: it resolves the episode's patient and facility, rejects unresolved facility attribution, calls `assert_patient_facility_context`, and requires active-facility equality for ordinary clinical roles. It exempts admin, IT admin and system superuser from that equality check; this privileged override should remain an explicit policy decision and should be audited. Preserve the function's exact 11-argument identity and empty search_path if it is later changed.

**Required repair:**
1. Replace `get_maternity_workspace` through a forward migration that resolves the caller's active facility once and fails closed for ordinary clinical roles when it is NULL.
2. Scope both episode and observation subqueries to the same facility, and require patient and episode facility attribution to agree. Do not treat NULL facility IDs as global.
3. For a requested episode ID, return a not-found/unauthorized response without disclosing whether a foreign-facility episode exists.
4. Define platform/global access explicitly; do not assume every admin role is entitled to unrestricted cross-facility maternity data.
5. Add regression tests for same-facility, foreign-facility, null-facility, patient/episode mismatch, null active facility, and privileged override cases.
6. Review `maternity_observations` policies as defense in depth. Their role-only policies do not constrain access through the parent episode; add parent facility authorization or revoke direct table access in favor of reviewed RPCs, after checking UI callsites.

No maternity or patient row contents were queried. No schema, policy, grant, or data changes were made.
