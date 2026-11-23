# Migration reconciliation status

**Assessment date:** 2026-11-23  
**Repository baseline inspected:** `main` at `2d12bc3d254e2f61ee00966583483c2fc5ade7e1`  
**Hosted database ledger:** `UNVERIFIED` (the connected Supabase account denied read access)  
**Local working tree:** `UNVERIFIED` (no local clone was available to inspect)

## Confirmed repository findings

The `main` migration directory contains 651 SQL files, but the current migration inventory contract does not pass:

- 21 duplicate 14-digit migration-version groups.
- One invalidly named SQL entry: `supabase/migrations/$(path)`.
- A clean replay is blocked before Supabase services start because the static migration contract rejects these entries.

The duplicate version groups are:

| Version | Conflicting migration files |
|---|---|
| `20260912003000` | `phase2_pharmacy_procedure_imaging_gates`, `phase4_triage` |
| `20260912010000` | `phase6_anesthetic_assessment_foundation`, `phase8_ai_clinical_provenance` |
| `20260912021000` | `attending_patient_history_summary`, `global_hims_operations` |
| `20260912024500` | `global_hims_enterprise_operations`, `global_hims_inpatient_emergency_theatre_insurance` |
| `20260912162000` | `clinical_change_audit_hardening`, `hims_workflow_completion` |
| `20260912200000` | `phase5_lab_catalogue_and_audit`, `prescription_payment_lifecycle_reconciliation` |
| `20260912250000` | `lab_direct_write_lockdown`, `reconciliation_finalization` |
| `20260913180000` | `reconcile_appointments_operational_workflow`, `reports_center_submission_rbac` |
| `20260914140000` | `clinical_direct_mutation_surface_hardening`, `theatre_emergency_transfusion_lifecycle_hardening` |
| `20260914150000` | `admission_bed_direct_mutation_reconciliation`, `clinical_claim_nursing_direct_mutation_hardening` |
| `20260914170000` | `clinical_insurance_case_direct_mutation_hardening`, `clinical_triage_medication_mutation_hardening` |
| `20260915170000` | `reassert_internal_security_definer_execute_hardening`, `remove_duplicate_insurance_claim_indexes` |
| `20260925200000` | `notification_advisor_finalization`, `notification_inbound_email_store` |
| `20260929100000` | `harden_ward_table_data_api_boundary`, `insurance_company_master_data` |
| `20260929103000` | `harden_operational_workspace_search_path`, `service_catalogue_department_control` |
| `20260929150000` | `canteen_dietary_operational_workspace`, `operational_workspace_scope_hardening`, `patient_canonical_insurer_linkage` |
| `20260929200000` | `fix_canteen_menu_rbac_realtime`, `role_dashboard_kpi_cleanup`, `secure_default_function_execute_privileges` |
| `20260929203000` | `active_dashboard_role_context`, `harden_security_definer_read_workspace_paths_batch6` |
| `20260930012000` | `harden_department_queue_multirole`, `harden_high_risk_rpc_execution_boundaries` |
| `20261002130000` | `pharmacy_global_catalogue_facility_stock_and_safety`, `scope_appointment_workflows_to_active_facility` |
| `20261002132500` | `patient_hub_read_rpc_get_compatibility`, `pharmacy_global_category_edit` |

## Existing reconciliation candidate

The branch `ci/future-proof-migration-contracts` is a useful source for investigation, not a safe wholesale merge target:

- It contains 659 SQL migration files, with no duplicate version groups and no invalid migration entry in the inspected directory.
- Relative to `main`, it is 327 commits ahead and 25 behind.
- Its migration-directory comparison shows 24 names removed and 32 added. It includes timestamp adjustments for colliding names and additional schema/security work.
- Three sampled timestamp-adjusted files were byte-for-byte identical to their old-name counterparts. This confirms those samples are filename/version adjustments, not SQL changes; it does not establish that the corresponding version identities match the live database ledger.
- The invalid `$(path)` SQL content in `main` appears under the valid filename `20261015090000_fix_workflow_notification_recipient_role.sql` on that branch, with identical Git blob content.

Because that branch is substantially divergent and contains other migration edits, do not merge it wholesale or copy its renumbered files into `main` until the hosted ledger has been compared. Replaying a renamed file can execute SQL again under a new migration identity.

## Required next reconciliation sequence

1. Obtain a read-only export of the hosted Supabase migration ledger (version and name) and inspect the local checkout's `supabase/migrations` directory.
2. Build a version/name/checksum comparison across local, GitHub `main`, the candidate branch, and each relevant hosted environment.
3. For every conflicting version, determine which file identity is recorded as applied in each environment. Mark unknown entries `UNVERIFIED`; do not guess.
4. Preserve all applied identities. Resolve collisions by selecting the canonical already-applied identity and, where needed, adding new forward-only repair migrations with versions greater than the current target baseline and confirmed hosted ledger.
5. Reconcile the malformed `$(path)` entry as a separate issue. Its SQL is not a valid Supabase migration filename on `main`; verify whether it was ever run manually before promoting its contents as a forward migration.
6. Run static inventory, clean replay, database contracts, representative upgrade-path tests, linked non-production ledger checks, schema/RLS/privilege checks, and application compatibility checks.
7. Only after all checks pass should the reviewed migration sequence be proposed for production deployment.

## Current gate results

| Gate | Status | Evidence |
|---|---|---|
| GitHub `main` inventory | `BLOCKED` | 21 duplicate versions and one invalid entry |
| Forward-only PR guard regression | `MATCH` | CI regression passed on PR #444 |
| New migration version guard | `MATCH` | CI guard passed against `origin/main` on PR #444 |
| Clean database replay | `BLOCKED` | Static migration contract stops before local Supabase startup |
| Hosted Supabase ledger | `UNVERIFIED` | Read access denied |
| Local checkout parity | `UNVERIFIED` | Local filesystem not available |
| Production readiness | `BLOCKED` | Do not deploy corrections until ledger and replay gates pass |

This report is an evidence snapshot, not an assertion that repository and hosted database parity has been achieved.
