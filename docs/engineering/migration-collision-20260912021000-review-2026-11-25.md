

## Follow-up catalog recheck (2026-11-25 13:30 UTC)

A focused read-only recheck refined the ACL and audit findings:

- `maternity_observations` still has no `facility_id`, no facility-lineage trigger, and only role-based SELECT/INSERT/UPDATE/DELETE policies. Its only observed trigger is the operational row-change audit trigger. Authenticated table grants observed are SELECT only; authenticated direct DML was not present in the effective grant listing. The immediate risk is therefore the role-only child-table read policy and any privileged RPC that returns these rows, not a claim that authenticated direct DML is enabled.
- `maternity_episodes` retains its facility-lineage trigger and two facility-aware SELECT policies. Its older clinical role policies coexist with those policies; review the combined permissive/restrictive policy semantics rather than assuming a single policy defines access.
- `get_attending_patient_history(uuid,uuid)` remains SECURITY DEFINER, authenticated/service_role executable, anon denied, and calls `assert_patient_facility_read_context` plus current-encounter ownership validation. Its live `pg_catalog, public` path is intentional observed state for this function; do not replace it with the older candidate definition.
- `record_system_audit(text,text,text,uuid,text,jsonb)` remains SECURITY DEFINER, anon denied, authenticated/service_role executable, and checks authentication only before accepting caller-provided action, module, entity, severity, and metadata. The live `system_audit_log` policy still describes actor-attributed INSERT, but the effective authenticated table grants observed do not include INSERT/UPDATE/DELETE. Preserve the later direct-DML revocation; focus the residual review on whether the generic RPC is too permissive for an authoritative audit stream.
- `facility_configuration` has authenticated SELECT with `USING (true)` and admin-only write policies. Anon has broad table-level grants in the role-grant listing, but no anon policy was observed; that is not evidence of anon row visibility. The table has no `facility_id` and is singleton-shaped, so changing it to per-facility configuration requires a separate product/data migration decision.
- Maternity episodes and observations both have an `audit_operational_row_change` trigger. Only maternity episodes have the observed facility-lineage trigger.

No maternity, patient, audit, or configuration row contents were queried during this recheck. No database writes or deployments occurred.
