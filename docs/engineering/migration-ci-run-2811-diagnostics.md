# Migration CI run #2811 diagnostics

**Date:** 2026-11-23  
**PR:** [#444](https://github.com/kingpumpski/harmony-health-hub/pull/444)  
**PR head:** `1315df389dc0643e58936416ed1cf027ac189287`  
**Merge test commit:** `091c43b231781a61829dd91bf710c9c00337b70f`  
**Migration contract run:** #2811 / `45219028534`  
**Quality run:** #8892 / `45219028915`

## Result

- Quality workflow: **passed**.
- Migration contract workflow: **failed**.
- Forward-only regression passed.
- Immutable-history and forward-version-ordering checks passed. The check reported two migration path changes compliant with its contract; repository latest version was `20261024070000`, hosted ledger latest was `20261026141054`.
- Dependency installation (`npm ci`) passed.
- Migration parity regression, migration-contract workflow regression, and laboratory panel privilege static contract all passed.
- The migration identity validator failed in both jobs on the same 21 duplicate version groups below.
- Supabase CLI setup, local database startup, clean replay, and post-replay schema/RPC/privilege/RLS verification were skipped. Therefore this run provides no clean replay result.

## Exact duplicate diagnostics

| Version | Conflicting migration files |
|---|---|
| `20260912003000` | `20260912003000_phase2_pharmacy_procedure_imaging_gates.sql`; `20260912003000_phase4_triage.sql` |
| `20260912010000` | `20260912010000_phase6_anesthetic_assessment_foundation.sql`; `20260912010000_phase8_ai_clinical_provenance.sql` |
| `20260912021000` | `20260912021000_attending_patient_history_summary.sql`; `20260912021000_global_hims_operations.sql` |
| `20260912024500` | `20260912024500_global_hims_enterprise_operations.sql`; `20260912024500_global_hims_inpatient_emergency_theatre_insurance.sql` |
| `20260912162000` | `20260912162000_clinical_change_audit_hardening.sql`; `20260912162000_hims_workflow_completion.sql` |
| `20260912200000` | `20260912200000_phase5_lab_catalogue_and_audit.sql`; `20260912200000_prescription_payment_lifecycle_reconciliation.sql` |
| `20260912250000` | `20260912250000_lab_direct_write_lockdown.sql`; `20260912250000_reconciliation_finalization.sql` |
| `20260913180000` | `20260913180000_reconcile_appointments_operational_workflow.sql`; `20260913180000_reports_center_submission_rbac.sql` |
| `20260914140000` | `20260914140000_clinical_direct_mutation_surface_hardening.sql`; `20260914140000_theatre_emergency_transfusion_lifecycle_hardening.sql` |
| `20260914150000` | `20260914150000_admission_bed_direct_mutation_reconciliation.sql`; `20260914150000_clinical_claim_nursing_direct_mutation_hardening.sql` |
| `20260914170000` | `20260914170000_clinical_insurance_case_direct_mutation_hardening.sql`; `20260914170000_clinical_triage_medication_mutation_hardening.sql` |
| `20260915170000` | `20260915170000_reassert_internal_security_definer_execute_hardening.sql`; `20260915170000_remove_duplicate_insurance_claim_indexes.sql` |
| `20260925200000` | `20260925200000_notification_advisor_finalization.sql`; `20260925200000_notification_inbound_email_store.sql` |
| `20260929100000` | `20260929100000_harden_ward_table_data_api_boundary.sql`; `20260929100000_insurance_company_master_data.sql` |
| `20260929103000` | `20260929103000_harden_operational_workspace_search_path.sql`; `20260929103000_service_catalogue_department_control.sql` |
| `20260929150000` | `20260929150000_canteen_dietary_operational_workspace.sql`; `20260929150000_operational_workspace_scope_hardening.sql`; `20260929150000_patient_canonical_insurer_linkage.sql` |
| `20260929200000` | `20260929200000_fix_canteen_menu_rbac_realtime.sql`; `20260929200000_role_dashboard_kpi_cleanup.sql`; `20260929200000_secure_default_function_execute_privileges.sql` |
| `20260929203000` | `20260929203000_active_dashboard_role_context.sql`; `20260929203000_harden_security_definer_read_workspace_paths_batch6.sql` |
| `20260930012000` | `20260930012000_harden_department_queue_multirole.sql`; `20260930012000_harden_high_risk_rpc_execution_boundaries.sql` |
| `20261002130000` | `20261002130000_pharmacy_global_catalogue_facility_stock_and_safety.sql`; `20261002130000_scope_appointment_workflows_to_active_facility.sql` |
| `20261002132500` | `20261002132500_patient_hub_read_rpc_get_compatibility.sql`; `20261002132500_pharmacy_global_category_edit.sql` |

The captured validator output on this head did not report the previously known unversioned `$(path)` artifact. The 21 duplicate groups remain sufficient to fail the identity gate.

## Repository provenance search

A branch-name search for `original`, `backup`, and `pre-supabase` returned no matching refs. Search for `development` returned `ci/continuous-development-quality-gate` and `hardening/development-blocker-prevention`; neither search result by itself establishes the original pre-Supabase project. A `supabase` search returned Supabase-related maintenance branches, not an identified legacy source branch. These are name searches, not exhaustive proof that no external clone, deleted ref, workstation, or backup exists.

## Required disposition

Keep PR #444 draft and unmerged. Do not mechanically rename or delete the 21 collision files, mark migrations as applied, create an empty replacement for the missing September baseline, or bypass the identity gate. The next valid step is still source-level provenance recovery and an approved per-collision ordering/dependency decision, followed by a complete clean replay and post-replay verification on a disposable database. No production SQL, schema, or migration ledger was changed by this investigation.
