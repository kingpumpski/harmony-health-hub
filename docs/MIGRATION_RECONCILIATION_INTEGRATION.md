# Migration reconciliation integration

## Branch and safety boundary

This work is isolated on `integration/migration-reconciliation`, based on `main`. The existing `main` and `fix/missing-ai-diagnosis-schema-migration` branches are preserved. This branch is not permission to merge or apply migrations.

## Current production baseline

The baseline remains `unreconciled`. The original SQL for production versions `20260916002251` and `20260916003113` has not been recovered. Production apply is prohibited. Candidate provenance is not verified provenance.

## Changes in this integration tranche

- Make an unresolved baseline a failing validation result (exit code 2), rather than a green workflow with a warning.
- Keep production apply fail-closed (exit code 1).
- Add runtime tests for unresolved baseline, read-only verify, exact allowlist, unexpected versions, ambiguous rows, duplicate versions, and malformed allowlist entries.
- Remove the production `db push --dry-run` validation path while baseline provenance is unresolved.
- Require an exact, reviewed pending-version allowlist before any production apply step.

## Still required before declaring migration repair complete

1. Recover or independently establish authoritative evidence for the two canonical baseline entries; do not fabricate SQL.
2. Produce a per-version mapping of production ledger to repository migrations using Git history and SQL identity, including renamed files and collisions.
3. Review all 97 changed migration files and every rename/version change against deployment history.
4. Resolve SQL/function signature compatibility with actual application callers; do not change RPC return types merely to repair quoting.
5. Run delimiter, filename, dependency, and schema-contract checks.
6. Run clean replay and supported upgrade replay against a disposable local database after the Docker/Supabase local runtime is operational.
7. Run application lint, typecheck, full tests, build, and relevant GitHub Actions for the exact integration commit.
8. Obtain explicit review and approval before changing baseline status or production apply permissions.

## Prohibited actions

No production `supabase db push`, no direct edits to `supabase_migrations.schema_migrations`, no `supabase migration repair`, no fabricated baseline migrations, no `supabase db reset` against production, and no merge to `main` without explicit approval and passing required checks.

## Defects exposed by CI and repairs added to this branch

The first CI pass found three independent classes of problems:

- The clean local Supabase startup stopped at `20260910215228_81137334-9a88-408e-b7f3-0993eb7b9918.sql` because `public.ai_diagnosis_suggestions` had not been created before RLS was enabled. This branch adds the missing timestamped prerequisite migrations for reference tables, symptom-to-ICD mapping, and AI diagnosis suggestions, and makes the RLS migration idempotently restore the expected relations/policies.
- The delimiter scan exposed malformed bare-dollar delimiters in the Patient Hub entrypoints, clinical diagnosis context hardening, and inpatient admission workflow. The corresponding SQL files now use matching tagged delimiters.
- The fix-branch version of the insurance financial migration changed the function return type to JSONB. This branch explicitly preserves the main branch's composite `public.insurance_claims` return type and changes only the delimiter.

The initial quality run passed the baseline-gate runtime test, then failed on the delimiter checker and skipped subsequent checks as expected after the failure. The initial migration replay did not reach the full chain: local Supabase startup failed on the missing AI diagnosis prerequisite. The repairs above are committed for the next CI run; they are not yet verified by a completed rerun.

These edits are integration candidates only until production migration history confirms whether the added historical versions are already recorded. Do not push them to production while the baseline is unreconciled.

- The second clean-replay attempt advanced past AI diagnosis and failed in `20260911233000_phase2_service_order_payment_gating.sql`: the pre-existing `department_queues` table from the May schema lacked `queued_at` (and the later phase expected `service_order_id`, `claimed_by`, and `claimed_at`). Its `CREATE TABLE IF NOT EXISTS` declaration did not alter the legacy table. This branch now adds and backfills those columns before the index and RPC definitions, while retaining the later compatibility migration.

- The next replay reached `20260912002000_phase5_patient_audit_retention.sql` and failed because the expected legacy relation `public.patient_audit_log` was absent. The fix-branch compatibility version is now applied to this integration branch: it guards both `patient_audit_log` and the canonical `patient_audit` table, and safely does nothing when neither exists. The static migration contract already asserts these guards.

- Static migration contract testing then found duplicate version `20260912003000` assigned to both `phase2_pharmacy_procedure_imaging_gates` and `phase4_triage`. The integration candidate now moves the triage file to `20260912003500`, matching the fix branch's content-identical rename. This resolves repository version uniqueness for replay, but it is a **production-history risk** until the remote ledger proves which migration was recorded under `20260912003000`. Do not apply this rename to production or merge it until that mapping is independently confirmed.

- The static contract then found a second duplicate migration version: `20260912010000` was assigned to both the Phase 6 anesthetic foundation and Phase 8 AI clinical provenance files. The AI provenance file is now moved to `20260912010001`, with content verified identical to the fix-branch rename. As with the Phase 4 triage rename, production ledger provenance must confirm which file was historically recorded as version `20260912010000` before merge/apply.
- The next replay exposed the bulk-import legacy schema collision: `20260912005000_phase7_bulk_import_hardening.sql` used `CREATE TABLE IF NOT EXISTS` then indexed `entity_type`, even though the May legacy table had `entity`, `filename`, and `inserted_rows`. The fix-branch compatibility block is now moved before index creation in the integration candidate. It maps preserved legacy values and derives source format only from a verifiable filename extension; unknown legacy values fail closed rather than being silently guessed.

## Duplicate-version normalization tranche

The fix-branch migration-version collision commit identifies 23 duplicate-version file renames. All 23 are now represented in this integration candidate with unique 14-digit versions. Twenty renames were content-identical; three also include substantive repairs that were reviewed and ported:
- The triage mutation grant now matches the actual 14-argument numeric RPC signature created earlier in the chain.
- The default function privilege migration guards changes to `supabase_admin` defaults based on current-role membership, avoiding permission failures during clean replay while retaining explicit PUBLIC/anon/authenticated revokes where authorized.
- High-risk RPC execution-boundary hardening now checks exact function signatures and only alters functions that exist, rather than failing replay when an optional historical RPC is absent.

These version changes remain candidate-only. Because duplicate versions make the historical production identity ambiguous, the remote migration ledger and deployment records must be reconciled before any of these renamed versions are allowed into production.

## Additional queue-writer and inventory findings (2026-11-03)

A follow-up review found that the covered-visit auto-release trigger in `20260914000000_patient_visit_coverage_activation.sql` also writes to the legacy `department_queues` table. Its former insert supplied only `service_order_id` and `department`, omitting the legacy required `patient_id` and `priority` values. It also used an `ON CONFLICT (service_order_id)` target that did not explicitly infer the partial unique index created for non-null service-order links. The integration branch now populates the legacy queue fields and uses `WHERE service_order_id IS NOT NULL`; the queue contract test now protects this trigger path as well as the migration column-ordering path. This is a source-level repair pending the current CI run and clean replay/runtime verification.

Read-only inspection of the connected production schema also found two foreign-key constraints on `department_queues.service_order_id` with different names but identical referenced-table definitions. Record this as duplicate-constraint drift. Do not drop either constraint until the migration provenance and dependent schema are reconciled; any cleanup must be a reviewed forward migration.

The checked-in `supabase-migration-list.txt` is not current evidence: its remote column contains 339 versions, whereas the connected production migration ledger returned 417 versions on 2026-11-03. The snapshot also contains repeated local version rows. Regenerate the inventory from the exact reviewed branch and fresh linked ledger before making version-mapping decisions. Do not use the stale snapshot to approve or repair the production baseline.

## Read-only production inspection (2026-11-03)

The connected Supabase project was inspected using read-only migration-history, catalog, privilege, and advisor queries. No production mutation was performed.

### Migration ledger and provenance

- The current production ledger contains 417 applied migration entries.
- The production baseline entries `20260916002251_canonical_remote_schema` and `20260916003113_fix_start_imaging_order_queue_contract` are present in the ledger, but their original SQL remains unrecovered.
- The attached evidence archive captured the fix-branch snapshot at commit `31645d93`: 661 local migration files and 417 remote entries, with 80 exact version overlaps, 581 local-only versions, and 337 remote-only versions. The local Supabase history command in that archive failed to connect to localhost port 54322, so no local database replay was established by that archive.
- Eight of the 23 renamed migration names have candidate name matches in the production ledger, but SQL identity is not established. The candidates are:
  - `notification_inbound_email_store` — remote version `20260925205248`
  - `insurance_company_master_data` — remote version `20260929063756`
  - `service_catalogue_department_control` — remote version `20260929063454`
  - `patient_canonical_insurer_linkage` — remote version `20260929081044`
  - `role_dashboard_kpi_cleanup` — remote version `20260929141826`
  - `harden_security_definer_read_workspace_paths_batch6` — remote version `20260929143830`
  - `scope_appointment_workflows_to_active_facility` — remote version `20261002052916`
  - `pharmacy_global_category_edit` — remote version `20261002132256`
- These are candidate mappings only. Do not mark any migration as applied or add it to an allowlist based on matching names alone.

### Current production schema findings

- The production schema already contains the AI diagnosis suggestion/reference tables, patient audit relations, diagnosis patient lineage, lab result patient lineage, department queue columns, and prescription compatibility fields. This confirms those objects exist in production today, even though clean replay from the repository exposed missing prerequisites/order defects.
- `bulk_import_jobs` remains on the legacy shape (`entity`, `filename`, `inserted_rows`) and currently has no rows. A new forward-only candidate migration adds the modern columns, preserves/backfills legacy values, and refuses to guess unknown entity types or file formats.
- `department_queues` and `billing_overrides` each have two identical service-order foreign keys. The forward candidate removes only the duplicate constraints and retains the canonical FK.
- `lab_result_attachments` has two identical btree indexes on `lab_result_id`. The forward candidate removes the redundant index.
- `lab_test_groups` and `lab_test_group_items` have RLS enabled but no policies, while client roles still hold table grants. The UI uses guarded SECURITY DEFINER RPCs for all panel reads/writes; the forward candidate revokes direct client table access and adds explicit restrictive deny policies.
- `public.ensure_updated_at()` is a trigger-only, SECURITY INVOKER function with no pinned search path and direct execute grants to client roles. The forward candidate pins `search_path=pg_catalog` and revokes direct execute while preserving its existing triggers.
- The security catalog contains 313 public SECURITY DEFINER functions; 279 are executable by authenticated users, zero are executable by anon, and all have a pinned search_path. The authenticated functions reviewed have auth/facility guards or delegate to guarded RPCs; two simple wrappers delegate to guarded functions. Therefore, do not blanket-revoke authenticated execution from all 279 functions. A database contract now protects the actual least-privilege invariants.

The new forward migration is candidate-only. It must remain blocked by the unresolved production baseline until the migration provenance review is approved.

### RLS policy performance findings

Read-only policy catalog inspection confirmed the facility identity policies are already **restrictive** policies, so they AND with the role/patient access policies; they are not the source of the permissive OR behavior. The remaining multiple-permissive-policy findings came from:
- Six internal notification tables, each with separate permissive false policies for `anon` and `authenticated`. These are now consolidated into one restrictive deny policy per table.
- `invoices` and `video_sessions`, each with distinct patient-own and staff-read permissive policies. These access paths are now combined into one OR expression per table, while existing restrictive facility guards remain unchanged.

The new pgTAP contract verifies that the patient-own and staff access paths remain present, facility guards remain restrictive, and internal notification tables remain inaccessible to both client roles.

### Verified insurance claim RPC return contracts

Read-only inspection of the live production catalog confirmed:
- `transition_insurance_claim_canonical(uuid,text,numeric,numeric,text,text)` returns PostgreSQL `json`, not `jsonb`.
- `update_insurance_claim_financials(uuid,numeric,numeric,text,text)` returns `public.insurance_claims` (the composite row type), not `jsonb`.

The migration-contract assertion inherited from the fix branch incorrectly expected JSONB for the transition RPC. It has been corrected to the live `json` contract. The integration branch preserves both production return types and adds a separate regression assertion for the composite financial RPC return type.

- The next clean replay reached `20260912027000_global_hims_workflow_reconciliation.sql` and exposed a return-type mismatch: the six-argument legacy `transition_insurance_claim` function had already been created as `RETURNS JSON` by `20260912025500`, while the main-branch reconciliation attempted `RETURNS JSONB`. The integration candidate now preserves `JSON`, with a source comment and static contract. This is confirmed by the production canonical transition RPC also returning `json`; the legacy overload is absent in current production and is later removed by the chain.

## Additional replay and API-compatibility findings (2026-11-03)

The migration replay subsequently exposed a medication-administration dependency: the legacy `medication_administrations` table was created with `drug_name`, `administered_at`, and `created_at`, while the later MAR migration indexed `scheduled_at`. The integration branch now inserts `20260912022900_reconcile_medication_administration_legacy_columns.sql` before the index migration. It backfills only from existing source fields, fails closed when required history cannot be established, and includes explicit `END;` terminators in all DO blocks.

The HIMS enterprise migration originally called `has_role(auth.uid(), app_role[])`, but the connected production database exposes only the scalar `has_role(uuid, app_role)` overload. The integration migration now uses explicit scalar role checks. The authenticated clinical RPC migration also uses an empty pinned search path.

A later replay exposed an incompatible return-type replacement for `transition_insurance_claim`: an earlier migration created the six-argument function as `RETURNS JSON`, while the later migration attempted `RETURNS JSONB`. The integration branch now preserves `JSON` for the legacy function and the canonical transition RPC, matching the connected production `transition_insurance_claim_canonical` return type. Regression contracts inspect both migration definitions. The claim financial RPC continues to preserve its separate `public.insurance_claims` return contract.

The optional `current_user_facility_id()` hardening in batch 5 is now guarded because the helper is introduced by a later migration; its later definition pins an empty search path. The RLS policy consolidation also wraps stable role helpers in `(SELECT ...)` and terminates its notification-policy DO block correctly.

The patient-audit foundation now enforces the action constraint on pre-existing legacy tables and avoids adding a redundant unique index when a primary key or equivalent unique index already protects `id`.

At this checkpoint, the integration branch contains 657 SQL migration files with 657 unique version prefixes. The current CI runs are still pending; this inventory does not substitute for a completed clean replay or full quality suite.

- A further clean-replay contract exposed the Reports Center seed RPC return-type transition. Earlier local migrations create `seed_facility_reports(uuid)` as `INTEGER`, but the live production function returns `void`, and the later reconciliation migration also defines `void`. The main-chain `CREATE OR REPLACE` attempted to change the return type and is invalid PostgreSQL. The integration candidate now explicitly drops the earlier function signature before recreating the production-verified `void` function, and a static contract enforces this ordering. The dependent facility-creation routine is PL/pgSQL and resolves the helper when invoked; clean replay must verify the dependency behavior.

- The live foreign-key catalog also identified four FK columns without supporting indexes: `hr_employees.archived_by`, `lab_result_attachments.uploaded_by`, `lab_test_group_items.test_id`, and `lab_test_groups.created_by`. The forward schema-advisor migration now adds those indexes, with pgTAP assertions for each.

### Additional clean-replay fixes and advisor review — 2026-11-03

- The replay failure in `20260912190000_module_workflow_reconciliation.sql` came from changing `transition_medication_administration(uuid,text,text,text,uuid)` from the established `JSONB` return type to the `medication_administrations` composite type. The preceding migration `20260912173000` explicitly transitions the earlier UUID function to JSONB, and production currently exposes JSONB. The workflow reconciliation and later patient-context hardening migrations now retain JSONB and return the documented JSON object shape. The live production function definition was inspected read-only; no production change was made.
- The tariff contract failure was caused by a clean-install schema mismatch: the early local table foundation declared legacy `category TEXT NOT NULL`, but the canonical production table uses nullable `specialty_category` and has no `category` column. The early foundation now permits the legacy category field to be null so the already-deployed canonical-alias migration can replay unchanged. The forward schema reconciliation copies any legacy category values into `specialty_category` where it is null, then drops the obsolete column. The deployed `20260919055127` migration itself was not modified; its production-configured amounts remain preserved because its upsert does not overwrite `amount`.
- The schema-advisor test plan now checks that the final tariff schema has `specialty_category` and no legacy `category`; the pgTAP assertion count is balanced at 32.
- The RLS advisor reported 12 multiple-permissive-policy warnings. The candidate consolidates the duplicated invoice, video-session, payroll-item, and payroll-period paths where semantics were equivalent. Eight role-specific access unions are intentionally retained: appointments, dental assessments, dietary assessments, dietary meal orders, ophthalmology assessments, physiotherapy assessments, physiotherapy treatment plans, and specialist review sessions. Their specialty write policies and general clinical read policies have different scopes; merging them into one broad policy or deleting one would alter authorization. New pgTAP assertions protect both paths on each table.
- The security advisor snapshot reports two RLS-enabled laboratory panel tables with no policies, one mutable-search-path trigger helper, and 279 authenticated-executable public SECURITY DEFINER functions. The candidate adds restrictive deny policies and removes direct client table grants for the two internal panel tables; pins `ensure_updated_at()` to `pg_catalog`, revokes direct client execution while retaining attached triggers, and tests that no public SECURITY DEFINER function is anon-executable and that all have a pinned search path. The 279 authenticated RPC warnings are not blanket-revoked: each function must be reviewed for its intended API exposure, authorization guard, and facility/patient scoping. The heuristic contract is a regression aid, not a substitute for that per-function review.
- The performance advisor reported one duplicate lab-result attachment index, addressed by the candidate. It also reports unused indexes; these are not dropped solely from a point-in-time advisor result because usage counters and workload windows must be reviewed first.
- Four missing FK-column indexes are included with explicit assertions: `hr_employees.archived_by`, `lab_result_attachments.uploaded_by`, `lab_test_group_items.test_id`, and `lab_test_groups.created_by`.

The latest clean-replay and Quality runs for the preceding head exposed the tariff contract mismatch and the medication transition return-type mismatch. The fixes above have been pushed to the integration branch; the new head's workflows must complete before any pass is claimed.
