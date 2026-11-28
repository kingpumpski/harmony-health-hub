# Public API-role ACL and RLS policy cross-check — 2026-11-28

## Scope

Read-only follow-up to the live public-table privilege inventory for Supabase project `ygqoptvezotdqhtimdkr`. This check compares effective table ACLs with the actual role targets and command scope of RLS policies on selected sensitive tables. No hosted changes were made.

## Findings

### Laboratory panel tables: high-priority ACL mismatch

- `lab_test_groups` and `lab_test_group_items` have RLS enabled but no RLS policies.
- Both still grant broad table privileges to `anon` and `authenticated`.
- With RLS enabled and no applicable policy, API roles cannot access rows through ordinary table queries, but the grants are still unnecessary and should be removed.
- The staged forward-only migration `20261127100100_harden_laboratory_panel_table_privileges_and_timestamp_trigger.sql` already revokes direct API-role access and retains the intended authenticated RPC path. This is the clearest existing candidate for a least-privilege correction, pending replay and runtime contract validation.

### Scheduled notifications: deny policies already exist

- `scheduled_notifications` has broad table ACLs for API roles.
- Its policies explicitly target `anon` and `authenticated`, each with command ALL and both USING and WITH CHECK set to false.
- This is a useful example of why ACL-only scans overstate practical row access. The broad grants remain poor privilege hygiene, but the deny policies are an additional effective RLS barrier for those roles.

### Sensitive tables: sampled policies target authenticated, not anon

The role-expanded policy inspection confirmed that sampled policies on `ai_case_memory`, `audit_logs`, `bulk_import_jobs`, `nursing_care_plans`, `nursing_shift_handovers`, `patient_audit`, `patient_audit_log`, and `system_audit_log` target `authenticated`. They do not target `anon` or PUBLIC.

This means the broad anon ACLs found in the aggregate inventory do not, by themselves, establish anonymous row access for these sampled tables. Authenticated policy semantics still need table-by-table review: role-only policies may require additional facility or ownership predicates for multi-facility clinical data.

### Nursing and audit findings remain distinct

- Nursing handover and care-plan authenticated ALL policies are role-based, while the facility isolation policies observed in the live catalog are SELECT-only. The staged nursing migration removes direct authenticated table privileges and retains SELECT, routing writes through reviewed facility-aware RPCs.
- Patient audit policies in the live catalog include broad authenticated role-based access, but the staged audit migration narrows the direct client surface to facility-scoped `patient_audit_log` reads and removes direct access to legacy snapshot storage. Both remain unapplied pending replay.

## Remediation priority

1. Keep the staged laboratory table ACL correction as the first narrowly scoped ACL repair; verify the RPCs and database contract in disposable PostgreSQL replay.
2. Keep the staged nursing and patient-audit corrections separate; they address distinct authenticated access and write-boundary problems.
3. Review authenticated role-only ALL policies on clinical and billing tables against facility, patient ownership, and operation-specific authorization. Do not assume the SELECT-only restrictive facility guards protect writes.
4. Retain the explicit scheduled-notification deny policies and consider removing unnecessary API-role table grants in a separately tested forward migration after confirming internal service-role/job execution paths.
5. Build a policy-aware audit contract that records table privilege, RLS enabled/forced status, policy command, policy target roles, USING, and WITH CHECK. Treat a policy as relevant only when its role target includes the current role or PUBLIC and its command applies to the attempted operation.

## Verification limits

This is a targeted catalog review, not a full 156-table policy proof or an exploit test. It does not inspect every view, RPC, Edge Function, service-role caller, or application code path. No table grants, policies, functions, or data were changed. The historical migration source mismatch and 21 duplicate migration-version groups still prevent clean replay.
