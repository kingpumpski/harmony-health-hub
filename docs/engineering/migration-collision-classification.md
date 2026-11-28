# Duplicate migration-version classification

**Date:** 2026-11-23  
**Repository branch:** `chore/forward-only-migration-governance`  
**Hosted project:** `ygqoptvezotdqhtimdkr`  
**Hosted ledger snapshot:** `supabase/migration-ledger-baseline.json` (417 entries)

## New read-only comparison result

I compared every one of the 21 duplicate version prefixes currently reported by the migration inventory against all 417 version keys in the captured hosted ledger.

**Result: 0 of the 21 duplicate version prefixes occur in the hosted ledger. All 21 are local-only version identities relative to this one linked Supabase project's captured ledger.**

This is useful evidence, but it does not establish that the SQL files were never executed. A file can have been applied under a different hosted version/name, run manually, or applied in a separate environment. The hosted ledger is an identity list, not a SQL checksum registry. The user's known original development environment predates Supabase and therefore is not represented by a Supabase migration ledger.

## Complete collision inventory

| Duplicate version | Files sharing that version | Exact version in linked hosted ledger |
|---|---|---|
| `20260912003000` | `phase2_pharmacy_procedure_imaging_gates`; `phase4_triage` | No |
| `20260912010000` | `phase6_anesthetic_assessment_foundation`; `phase8_ai_clinical_provenance` | No |
| `20260912021000` | `attending_patient_history_summary`; `global_hims_operations` | No |
| `20260912024500` | `global_hims_enterprise_operations`; `global_hims_inpatient_emergency_theatre_insurance` | No |
| `20260912162000` | `clinical_change_audit_hardening`; `hims_workflow_completion` | No |
| `20260912200000` | `phase5_lab_catalogue_and_audit`; `prescription_payment_lifecycle_reconciliation` | No |
| `20260912250000` | `lab_direct_write_lockdown`; `reconciliation_finalization` | No |
| `20260913180000` | `reconcile_appointments_operational_workflow`; `reports_center_submission_rbac` | No |
| `20260914140000` | `clinical_direct_mutation_surface_hardening`; `theatre_emergency_transfusion_lifecycle_hardening` | No |
| `20260914150000` | `admission_bed_direct_mutation_reconciliation`; `clinical_claim_nursing_direct_mutation_hardening` | No |
| `20260914170000` | `clinical_insurance_case_direct_mutation_hardening`; `clinical_triage_medication_mutation_hardening` | No |
| `20260915170000` | `reassert_internal_security_definer_execute_hardening`; `remove_duplicate_insurance_claim_indexes` | No |
| `20260925200000` | `notification_advisor_finalization`; `notification_inbound_email_store` | No |
| `20260929100000` | `harden_ward_table_data_api_boundary`; `insurance_company_master_data` | No |
| `20260929103000` | `harden_operational_workspace_search_path`; `service_catalogue_department_control` | No |
| `20260929150000` | `canteen_dietary_operational_workspace`; `operational_workspace_scope_hardening`; `patient_canonical_insurer_linkage` | No |
| `20260929200000` | `fix_canteen_menu_rbac_realtime`; `role_dashboard_kpi_cleanup`; `secure_default_function_execute_privileges` | No |
| `20260929203000` | `active_dashboard_role_context`; `harden_security_definer_read_workspace_paths_batch6` | No |
| `20260930012000` | `harden_department_queue_multirole`; `harden_high_risk_rpc_execution_boundaries` | No |
| `20261002130000` | `pharmacy_global_catalogue_facility_stock_and_safety`; `scope_appointment_workflows_to_active_facility` | No |
| `20261002132500` | `patient_hub_read_rpc_get_compatibility`; `pharmacy_global_category_edit` | No |

The table omits the `.sql` suffix only to keep the inventory readable; filenames are exactly the names recorded in the CI inventory report.

## What this proves—and what it does not

- **Proves:** none of the 21 duplicate prefixes is an exact version key in the captured 417-row ledger for the linked project.
- **Does not prove:** that any conflicting SQL is unapplied, that one file is disposable, that a file's current body matches what ran historically, or that there are no other Supabase projects/environments.
- **Does not authorize:** choosing a winner, deleting a file, renumbering a file, marking it applied, or running any of these SQL files against production.

## Safe path to resolve the duplicate gate

1. Preserve all 21 collision groups and their current contents unchanged as historical source evidence.
2. Recover the missing original `20260916002251_canonical_remote_schema` baseline or agree on a separately versioned, explicitly documented bootstrap baseline. A current live-schema dump must be labelled as a current snapshot, never misrepresented as the missing September baseline.
3. For each collision group, establish whether either SQL body is already represented by the canonical baseline or by a later hosted migration. Compare SQL semantics and schema effects; version absence alone is insufficient.
4. If the original history cannot be reconstructed, design a deliberate bootstrap cutover: preserve the legacy migration archive outside the active replay chain, create a verified baseline for new empty databases, and define a separate supported upgrade/reconciliation path for existing databases. This requires maintainer approval and tests; it is not a mechanical rename operation.
5. Only after the bootstrap/upgrade strategy is approved should the active migration inventory contract be changed. It must continue to reject duplicate active versions, while tests prove archived source preservation and the documented bootstrap replay.
6. Run the clean replay and schema/RPC/security contracts on an isolated database. Keep production untouched until independent ledger and schema verification pass.

## Current disposition

The migration identity gate still fails on the 21 duplicate groups. This new comparison narrows the evidence: all 21 collision version keys are absent from the linked hosted ledger. It does not remove the ambiguity about SQL execution history or supply the missing canonical baseline. PR #444 remains draft; no collision was renamed, deleted, or executed, and no production migration was applied.
