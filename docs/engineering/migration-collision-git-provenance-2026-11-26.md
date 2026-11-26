# Git-history provenance for duplicate migration versions — 2026-11-26

## Evidence boundary

GitHub path history was queried for all 44 SQL files in the 21 duplicate-version groups. This records the latest commit returned for each exact path: abbreviated SHA, commit author timestamp, and subject. The original uploaded ZIP had no Git history, but the current repository retains path-level commit provenance.

These records are evidence of source-control chronology, not proof that a migration ran in a Supabase environment. Commit author timestamps can be rewritten and do not replace signed release artifacts or database migration logs. A shared commit does not establish relative order between files it changes.

## Latest path commit evidence

| Colliding version | Migration file | Latest path commit | Author timestamp (UTC) | Commit subject |
|---|---|---|---|---|
| `20260912003000` | `phase2_pharmacy_procedure_imaging_gates.sql` | `b5a6826c` | 2026-09-11 23:34:27Z | feat: complete phase 2 pharmacy procedure and imaging payment gates |
| `20260912003000` | `phase4_triage.sql` | `b7519672` | 2026-09-11 23:58:47Z | feat: add persistent triage assessments and clinical priority audit |
| `20260912010000` | `phase6_anesthetic_assessment_foundation.sql` | `eab6ad4c` | 2026-09-12 00:18:13Z | feat: add anesthetic assessment persistence and clinical safeguards |
| `20260912010000` | `phase8_ai_clinical_provenance.sql` | `7930a828` | 2026-09-12 00:28:32Z | feat: add clinical AI provenance and review audit model |
| `20260912021000` | `attending_patient_history_summary.sql` | `a34225c2` | 2026-09-12 00:56:04Z | feat: add attending patient history summary RPC |
| `20260912021000` | `global_hims_operations.sql` | `2327065d` | 2026-09-12 01:21:06Z | feat: add global HIMS operations foundation |
| `20260912024500` | `global_hims_enterprise_operations.sql` | `dc4964fa` | 2026-09-12 01:31:19Z | feat: add enterprise clinical operations foundations |
| `20260912024500` | `global_hims_inpatient_emergency_theatre_insurance.sql` | `af7063bf` | 2026-09-12 01:37:34Z | feat: expand global HIMS inpatient emergency theatre transfusion insurance |
| `20260912162000` | `clinical_change_audit_hardening.sql` | `f101a219` | 2026-09-12 16:09:26Z | fix: lock down clinical audit trigger function |
| `20260912162000` | `hims_workflow_completion.sql` | `ae7c01a5` | 2026-09-12 16:11:30Z | fix: enforce server-side HIMS workflow transitions |
| `20260912200000` | `phase5_lab_catalogue_and_audit.sql` | `2d2d727e` | 2026-09-12 00:04:39Z | feat: add lab catalogue and patient audit trail |
| `20260912200000` | `prescription_payment_lifecycle_reconciliation.sql` | `e73d28ff` | 2026-09-12 19:49:22Z | fix: reconcile prescription payment and dispensing lifecycle |
| `20260912250000` | `lab_direct_write_lockdown.sql` | `cc9bd846` | 2026-09-12 20:58:25Z | security: finalize laboratory write lockdown after secure RPC reconciliation |
| `20260912250000` | `reconciliation_finalization.sql` | `f3414fb1` | 2026-09-12 21:00:30Z | security: finalize HIMS operational direct-write lockdown |
| `20260913180000` | `reconcile_appointments_operational_workflow.sql` | `8f119976` | 2026-09-13 17:11:38Z | security: reconcile appointment operational workflow |
| `20260913180000` | `reports_center_submission_rbac.sql` | `95032b12` | 2026-09-13 23:09:15Z | fix(reports): make submission RBAC migration valid |
| `20260914140000` | `clinical_direct_mutation_surface_hardening.sql` | `a1c344bc` | 2026-09-14 11:35:48Z | fix: harden direct clinical mutation surfaces |
| `20260914140000` | `theatre_emergency_transfusion_lifecycle_hardening.sql` | `28da9414` | 2026-09-14 11:30:57Z | fix: harden theatre emergency and transfusion lifecycle |
| `20260914150000` | `admission_bed_direct_mutation_reconciliation.sql` | `4a536575` | 2026-09-14 11:42:59Z | fix: harden admission bed and encounter mutation surfaces |
| `20260914150000` | `clinical_claim_nursing_direct_mutation_hardening.sql` | `56a74fa5` | 2026-09-14 11:41:23Z | fix: reconcile claim nursing and ward mutation boundaries |
| `20260914170000` | `clinical_insurance_case_direct_mutation_hardening.sql` | `5b2bfb48` | 2026-09-14 12:04:46Z | fix: harden insurance case mutation surface |
| `20260914170000` | `clinical_triage_medication_mutation_hardening.sql` | `8d1295a8` | 2026-09-14 12:01:34Z | fix: harden triage and medication mutation surfaces |
| `20260915170000` | `reassert_internal_security_definer_execute_hardening.sql` | `871d18de` | 2026-09-15 15:50:00Z | security: reassert internal SECURITY DEFINER RPC boundary |
| `20260915170000` | `remove_duplicate_insurance_claim_indexes.sql` | `77f22a76` | 2026-09-15 15:51:31Z | perf: remove duplicate insurance claim indexes |
| `20260925200000` | `notification_advisor_finalization.sql` | `b7ea7773` | 2026-09-25 16:30:43Z | fix(notification): finalize advisor-safe facility policies |
| `20260925200000` | `notification_inbound_email_store.sql` | `e06e94d9` | 2026-09-25 20:52:57Z | feat: add inbound email storage for notification webhooks |
| `20260929100000` | `harden_ward_table_data_api_boundary.sql` | `3c41c791` | 2026-09-29 06:28:28Z | fix: harden ward table data API boundary |
| `20260929100000` | `insurance_company_master_data.sql` | `8b5f38a4` | 2026-09-29 06:37:47Z | feat: add governed insurance company master data (#176) |
| `20260929103000` | `harden_operational_workspace_search_path.sql` | `3ca89e68` | 2026-09-29 06:30:43Z | fix: harden operational workspace search path |
| `20260929103000` | `service_catalogue_department_control.sql` | `9253cdd8` | 2026-09-29 06:33:21Z | feat: govern departmental service catalogue updates |
| `20260929150000` | `canteen_dietary_operational_workspace.sql` | `72b574de` | 2026-09-29 09:55:21Z | feat: build canteen dietary operational workspace |
| `20260929150000` | `operational_workspace_scope_hardening.sql` | `87e44de3` | 2026-09-29 14:47:56Z | fix: harden operational workspace scope boundaries |
| `20260929150000` | `patient_canonical_insurer_linkage.sql` | `6da42424` | 2026-09-29 08:10:22Z | feat: add governed patient canonical insurer linkage |
| `20260929200000` | `fix_canteen_menu_rbac_realtime.sql` | `7a0b427c` | 2026-09-29 14:28:53Z | fix: restore canteen menu RLS and realtime authorization |
| `20260929200000` | `role_dashboard_kpi_cleanup.sql` | `7eff6c34` | 2026-09-29 14:17:57Z | fix: remove unrelated pharmacist dashboard KPI |
| `20260929200000` | `secure_default_function_execute_privileges.sql` | `d4ab4050` | 2026-09-29 21:44:22Z | security(db): harden default function execute for migration owners |
| `20260929203000` | `active_dashboard_role_context.sql` | `a9abfc86` | 2026-09-29 14:24:27Z | feat: add server-validated active dashboard role context |
| `20260929203000` | `harden_security_definer_read_workspace_paths_batch6.sql` | `3711af01` | 2026-09-29 14:37:51Z | security: harden read workspace SECURITY DEFINER paths batch 6 |
| `20260930012000` | `harden_department_queue_multirole.sql` | `742c298f` | 2026-09-30 11:56:26Z | fix: harden SECURITY DEFINER search paths |
| `20260930012000` | `harden_high_risk_rpc_execution_boundaries.sql` | `3a198b8b` | 2026-09-30 00:48:13Z | security: correct lab RPC execution signature |
| `20261002130000` | `pharmacy_global_catalogue_facility_stock_and_safety.sql` | `bf0f0cb9` | 2026-10-02 13:22:41Z | feat: maintain global medication categories safely |
| `20261002130000` | `scope_appointment_workflows_to_active_facility.sql` | `b6dc3732` | 2026-10-02 05:28:49Z | fix: repair Patient Hub history and facility-scoped appointments |
| `20261002132500` | `patient_hub_read_rpc_get_compatibility.sql` | `188ef53f` | 2026-10-02 13:39:42Z | Fix Patient Hub read RPC GET compatibility |
| `20261002132500` | `pharmacy_global_category_edit.sql` | `bf0f0cb9` | 2026-10-02 13:22:41Z | feat: maintain global medication categories safely |

## Findings

- All 44 collision candidates have discoverable path-specific commit history.
- Most candidates have distinct commit timestamps, providing a chronological signal for a separate fresh-install sequence.
- `20260912024500` candidates have distinct commits six minutes apart but overlapping table definitions; chronology does not resolve their schema conflict.
- The `20260929200000` / `20260929203000` candidates have function and default-privilege dependencies documented in the static interaction review. Their order must preserve those dependencies.
- `20261002130000_pharmacy_global_catalogue_facility_stock_and_safety.sql` and `20261002132500_pharmacy_global_category_edit.sql` share latest commit `bf0f0cb9`; their relative execution order must be derived from SQL dependencies, not commit ordering.
- `20260912162000_clinical_change_audit_hardening.sql` and `20260912162000_hims_workflow_completion.sql` each have multiple path commits; the table records the latest commit, not the initial creation commit.

## Remediation use

1. Inspect each complete path diff and parent tree to confirm which commit introduced the current SQL body and whether later fixes changed it.
2. Compare exact SQL bytes with hosted migration ledger and catalog evidence. A filename match at another timestamp is only a lead.
3. Build a dependency graph covering object creation, function signatures, dynamic `pg_get_functiondef` transformations, default privileges, RLS, triggers, and grants.
4. Use commit chronology as one input to a separate fresh-install sequence, then validate it on disposable PostgreSQL 17 and compare catalog fingerprints.
5. Keep canonical hosted history unchanged. Do not synthesize ledger rows, rename files solely to pass uniqueness, or apply migrations to the hosted project during this repository-only phase.

## Disposition

The 21 duplicate-version groups remain a hard preflight blocker. This report improves source provenance but does not authorize renaming, deleting, reordering, merging, or applying migrations. No Supabase branch was created and no database was modified.