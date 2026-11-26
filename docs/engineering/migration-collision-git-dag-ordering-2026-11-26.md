# Migration collision Git-DAG ordering review — 2026-11-26

## Purpose

This review supplements the path-level author timestamps in `migration-collision-git-provenance-2026-11-26.md`. For each colliding migration path, it compares the latest path-specific commit recorded there using GitHub's commit-graph ancestry (merge-base / ahead / behind), rather than treating author timestamps as the ordering source.

The comparison answers only whether one recorded path commit is an ancestor of another. It does **not** prove when a migration was deployed, whether the hosted database ran either file, or whether the current SQL bodies are compatible. The compared commits are the latest commits touching each path, not necessarily the original creation commits.

## Results

For a comparison with candidate A as the base and candidate B as the head:
- `ahead`: B descends from A, so A's recorded path commit is an ancestor of B's.
- `behind`: B is an ancestor of A.
- `diverged`: neither commit is an ancestor of the other.

| Duplicate version | Git-DAG result | Ancestor order / disposition |
|---|---|---|
| `20260912003000` | Ordered | `phase2_pharmacy_procedure_imaging_gates` (b5a6826c) → `phase4_triage` (b7519672) |
| `20260912010000` | Ordered | `phase6_anesthetic_assessment_foundation` (eab6ad4c) → `phase8_ai_clinical_provenance` (7930a828) |
| `20260912021000` | Ordered | `attending_patient_history_summary` (a34225c2) → `global_hims_operations` (2327065d) |
| `20260912024500` | Ordered, schema conflict remains | `global_hims_enterprise_operations` (dc4964fa) → `global_hims_inpatient_emergency_theatre_insurance` (af7063bf). Both define the same five tables differently; ancestry does not resolve the DDL conflict. |
| `20260912162000` | **Diverged** | `clinical_change_audit_hardening` (f101a219) and `hims_workflow_completion` (ae7c01a5) are on diverged commit histories (11 commits unique to the first side and 3 unique to the second from merge base 090e2163). No source order can be inferred from ancestry. |
| `20260912200000` | Ordered | `phase5_lab_catalogue_and_audit` (2d2d727e) → `prescription_payment_lifecycle_reconciliation` (e73d28ff) |
| `20260912250000` | Ordered | `lab_direct_write_lockdown` (cc9bd846) → `reconciliation_finalization` (f3414fb1). The overlapping lab revocations still require full privilege-matrix comparison. |
| `20260913180000` | Ordered | `reconcile_appointments_operational_workflow` (8f119976) → `reports_center_submission_rbac` (95032b12) |
| `20260914140000` | Ordered | `theatre_emergency_transfusion_lifecycle_hardening` (28da9414) → `clinical_direct_mutation_surface_hardening` (a1c344bc) |
| `20260914150000` | Ordered | `clinical_claim_nursing_direct_mutation_hardening` (56a74fa5) → `admission_bed_direct_mutation_reconciliation` (4a536575) |
| `20260914170000` | Ordered | `clinical_triage_medication_mutation_hardening` (8d1295a8) → `clinical_insurance_case_direct_mutation_hardening` (5b2bfb48) |
| `20260915170000` | Ordered | `reassert_internal_security_definer_execute_hardening` (871d18de) → `remove_duplicate_insurance_claim_indexes` (77f22a76) |
| `20260925200000` | Ordered | `notification_advisor_finalization` (b7ea7773) → `notification_inbound_email_store` (e06e94d9) |
| `20260929100000` | Ordered | `harden_ward_table_data_api_boundary` (3c41c791) → `insurance_company_master_data` (8b5f38a4) |
| `20260929103000` | Ordered | `harden_operational_workspace_search_path` (3ca89e68) → `service_catalogue_department_control` (9253cdd8) |
| `20260929150000` | Ordered three-way chain | `patient_canonical_insurer_linkage` (6da42424) → `canteen_dietary_operational_workspace` (72b574de) → `operational_workspace_scope_hardening` (87e44de3) |
| `20260929200000` | Ordered three-way chain | `role_dashboard_kpi_cleanup` (7eff6c34) → `fix_canteen_menu_rbac_realtime` (7a0b427c) → `secure_default_function_execute_privileges` (d4ab4050) |
| `20260929203000` | Ordered | `active_dashboard_role_context` (a9abfc86) → `harden_security_definer_read_workspace_paths_batch6` (3711af01) |
| `20260930012000` | Ordered | `harden_high_risk_rpc_execution_boundaries` (3a198b8b) → `harden_department_queue_multirole` (742c298f) |
| `20261002130000` | Ordered | `scope_appointment_workflows_to_active_facility` (b6dc3732) → `pharmacy_global_catalogue_facility_stock_and_safety` (bf0f0cb9) |
| `20261002132500` | Ordered | `pharmacy_global_catalogue_facility_stock_and_safety` (bf0f0cb9) → `patient_hub_read_rpc_get_compatibility` (188ef53f). The pharmacy category-edit file shares the bf0f0cb9 commit with the preceding pharmacy candidate; its relative order is not resolved by this pairwise comparison. |

## Interpretation

- **20 of 21 duplicate-version groups** have a linear ancestor ordering among their latest path-specific commits. The two three-file groups also form linear chains.
- **One group (`20260912162000`) is genuinely divergent** in the commit graph. It needs source-level dependency analysis and, if possible, original release/deployment evidence.
- The `20260912024500` pair is chronologically ordered in Git but remains unsafe to replay as-is because its two `CREATE TABLE IF NOT EXISTS` definitions disagree on shared tables.
- For `20261002130000`, Git ancestry places appointment-scope before the pharmacy catalogue candidate. The pharmacy candidate and `20261002132500_pharmacy_global_category_edit.sql` share a latest path commit, so that commit does not order those two files.
- For `20260929200000`, the graph orders the dashboard KPI function before the canteen RLS file and both before the default-privilege file. This is a useful ordering lead, but the actual function-body transformation dependency and default-privilege owner semantics still require source and replay checks.

## Next implementation sequence

1. Resolve the divergent `20260912162000` group by comparing full blobs, parent trees, function/table dependencies, and any available deployment artifacts. Do not select an order from author timestamps.
2. Build a signature-aware dependency map for the `20260929200000` → `20260929203000` dashboard transformation and default-privilege boundary.
3. Reconcile the five shared tables in `20260912024500` against an authoritative schema snapshot before preparing any fresh-install sequence.
4. Use the ordered groups as candidate constraints in a **separate** fresh-install sequence; retain all original migration files and hosted ledger identities unchanged.
5. Validate the proposed sequence on disposable PostgreSQL 17 and compare schema, function signatures, owners, ACLs, RLS policies, triggers, and indexes before considering adoption.

## Safety disposition

This is repository evidence only. No migration file was renamed, deleted, merged, or reordered. No migration was applied, no Supabase branch was created, and no database was modified. The 21 duplicate-version groups remain a hard migration preflight blocker; clean replay must remain stopped until identity and schema reconciliation is complete.
