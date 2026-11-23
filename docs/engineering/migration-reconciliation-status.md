# Live migration reconciliation report

**Inspection date:** 2026-11-23  
**Supabase project:** `harmony-health-hub` (`ygqoptvezotdqhtimdkr`)  
**Project status:** `ACTIVE_HEALTHY`  
**Region / database:** `eu-central-1` / PostgreSQL 17.6.1.166  
**Git baseline inspected:** `main`  
**Local checkout:** `UNVERIFIED` — no local working tree is exposed to this session.

## Executive result

The live Supabase migration ledger is now readable. The repository and hosted history are **not aligned**. Do not merge timestamp-renumbering branches or apply a bulk migration repair until every historical identity is reconciled.

| Measure | Observed |
|---|---:|
| Hosted migration ledger rows | 417 |
| Hosted distinct versions | 417 |
| Hosted repeated migration names | 3 name groups |
| `main` SQL files | 651 |
| `main` unique timestamp versions | 628 |
| `main` duplicate timestamp groups | 21 |
| `main` invalid migration directory entries | 1 (`$(path)`) |
| Hosted entries matching a `main` migration name (after stripping embedded timestamp prefixes) | 333 |
| Of those, exact hosted version and file version matches | 77 |
| Matching names with different version timestamps | 256 |
| Hosted entries with no matching migration filename in `main` | 84 |
| Public tables reported | 156 |
| Public tables with RLS enabled | 156 |
| Public tables without RLS | 0 |

**Interpretation:** a matching SQL filename suffix does not prove the version identity is correct. 256 hosted entries have a corresponding current filename by name, but the 14-digit version in the file differs from the version recorded in Supabase. This is consistent with historical timestamp renumbering after application and must be reconciled using the original applied SQL, not guessed from names.

## 1. Current main migration timestamp collisions

`main` contains 21 groups of duplicate version timestamps and one invalid entry named `$(path)`. These make the migration directory fail its static inventory contract and the timestamp collisions make the chain ambiguous for replay.

| Version | Conflicting files |
|---|---|
| `20260912003000` | `20260912003000_phase2_pharmacy_procedure_imaging_gates.sql`<br>`20260912003000_phase4_triage.sql` |
| `20260912010000` | `20260912010000_phase6_anesthetic_assessment_foundation.sql`<br>`20260912010000_phase8_ai_clinical_provenance.sql` |
| `20260912021000` | `20260912021000_attending_patient_history_summary.sql`<br>`20260912021000_global_hims_operations.sql` |
| `20260912024500` | `20260912024500_global_hims_enterprise_operations.sql`<br>`20260912024500_global_hims_inpatient_emergency_theatre_insurance.sql` |
| `20260912162000` | `20260912162000_clinical_change_audit_hardening.sql`<br>`20260912162000_hims_workflow_completion.sql` |
| `20260912200000` | `20260912200000_phase5_lab_catalogue_and_audit.sql`<br>`20260912200000_prescription_payment_lifecycle_reconciliation.sql` |
| `20260912250000` | `20260912250000_lab_direct_write_lockdown.sql`<br>`20260912250000_reconciliation_finalization.sql` |
| `20260913180000` | `20260913180000_reconcile_appointments_operational_workflow.sql`<br>`20260913180000_reports_center_submission_rbac.sql` |
| `20260914140000` | `20260914140000_clinical_direct_mutation_surface_hardening.sql`<br>`20260914140000_theatre_emergency_transfusion_lifecycle_hardening.sql` |
| `20260914150000` | `20260914150000_admission_bed_direct_mutation_reconciliation.sql`<br>`20260914150000_clinical_claim_nursing_direct_mutation_hardening.sql` |
| `20260914170000` | `20260914170000_clinical_insurance_case_direct_mutation_hardening.sql`<br>`20260914170000_clinical_triage_medication_mutation_hardening.sql` |
| `20260915170000` | `20260915170000_reassert_internal_security_definer_execute_hardening.sql`<br>`20260915170000_remove_duplicate_insurance_claim_indexes.sql` |
| `20260925200000` | `20260925200000_notification_advisor_finalization.sql`<br>`20260925200000_notification_inbound_email_store.sql` |
| `20260929100000` | `20260929100000_harden_ward_table_data_api_boundary.sql`<br>`20260929100000_insurance_company_master_data.sql` |
| `20260929103000` | `20260929103000_harden_operational_workspace_search_path.sql`<br>`20260929103000_service_catalogue_department_control.sql` |
| `20260929150000` | `20260929150000_canteen_dietary_operational_workspace.sql`<br>`20260929150000_operational_workspace_scope_hardening.sql`<br>`20260929150000_patient_canonical_insurer_linkage.sql` |
| `20260929200000` | `20260929200000_fix_canteen_menu_rbac_realtime.sql`<br>`20260929200000_role_dashboard_kpi_cleanup.sql`<br>`20260929200000_secure_default_function_execute_privileges.sql` |
| `20260929203000` | `20260929203000_active_dashboard_role_context.sql`<br>`20260929203000_harden_security_definer_read_workspace_paths_batch6.sql` |
| `20260930012000` | `20260930012000_harden_department_queue_multirole.sql`<br>`20260930012000_harden_high_risk_rpc_execution_boundaries.sql` |
| `20261002130000` | `20261002130000_pharmacy_global_catalogue_facility_stock_and_safety.sql`<br>`20261002130000_scope_appointment_workflows_to_active_facility.sql` |
| `20261002132500` | `20261002132500_patient_hub_read_rpc_get_compatibility.sql`<br>`20261002132500_pharmacy_global_category_edit.sql` |

## 2. Hosted migrations whose version differs from the current main filename

The following list is complete for the 256 same-name mappings discovered by normalizing the optional embedded timestamp in the ledger name. The file currently in `main` must not be assumed to be the exact SQL body originally applied under the hosted version.

| Hosted version | Hosted ledger name | Current main file |
|---|---|---|
| `20260916094245` | `harden_service_order_override_and_release_contract` | `20260916100000_harden_service_order_override_and_release_contract.sql` |
| `20260916103904` | `optimize_rls_auth_uid_initplans` | `20260916110000_optimize_rls_auth_uid_initplans.sql` |
| `20260916105508` | `harden_internal_trigger_function_execute_boundary` | `20260916112000_harden_internal_trigger_function_execute_boundary.sql` |
| `20260916110729` | `harden_authorization_helper_execute_boundary` | `20260916113000_harden_authorization_helper_execute_boundary.sql` |
| `20260916205934` | `harden_record_system_audit_execute_boundary` | `20260916114500_harden_record_system_audit_execute_boundary.sql` |
| `20260917100222` | `20260917101500_harden_service_order_release_execution` | `20260917101500_harden_service_order_release_execution.sql` |
| `20260917112143` | `expand_master_data_migration_and_legacy_records` | `20260917120000_expand_master_data_migration_and_legacy_records.sql` |
| `20260917112203` | `add_reference_data_import_rpcs` | `20260917120500_add_reference_data_import_rpcs.sql` |
| `20260918064318` | `expand_master_data_migration_and_legacy_records` | `20260917120000_expand_master_data_migration_and_legacy_records.sql` |
| `20260918064331` | `add_reference_data_import_rpcs` | `20260917120500_add_reference_data_import_rpcs.sql` |
| `20260918064345` | `legacy_migration_reconciliation_approval` | `20260917130000_legacy_migration_reconciliation_approval.sql` |
| `20260918064407` | `clinical_admission_referral_document_lifecycle` | `20260917150000_clinical_admission_referral_document_lifecycle.sql` |
| `20260918064421` | `facility_financial_override_configuration` | `20260917151000_facility_financial_override_configuration.sql` |
| `20260918064426` | `specialist_referral_queue_security` | `20260917152000_specialist_referral_queue_security.sql` |
| `20260918064432` | `encounter_workflow_workspace_rpc` | `20260917153000_encounter_workflow_workspace_rpc.sql` |
| `20260918064438` | `default_streamlined_clinical_routing` | `20260917154000_default_streamlined_clinical_routing.sql` |
| `20260918064444` | `specialist_referral_appointment_bridge` | `20260917160000_specialist_referral_appointment_bridge.sql` |
| `20260918064451` | `admission_override_queue_reconciliation` | `20260917163000_admission_override_queue_reconciliation.sql` |
| `20260918064501` | `billing_tariff_adjustment_workflow` | `20260917170000_billing_tariff_adjustment_workflow.sql` |
| `20260918064509` | `imaging_result_clinician_notification` | `20260917200000_imaging_result_clinician_notification.sql` |
| `20260918064515` | `discharge_accounts_reconciliation_handoff` | `20260917210000_discharge_accounts_reconciliation_handoff.sql` |
| `20260918064522` | `discharge_billing_reconciliation_rpc` | `20260917223000_discharge_billing_reconciliation_rpc.sql` |
| `20260918064528` | `discharge_insurance_claim_bridge` | `20260917230000_discharge_insurance_claim_bridge.sql` |
| `20260918064630` | `insurance_claim_lifecycle_reconciliation` | `20260917233000_insurance_claim_lifecycle_reconciliation.sql` |
| `20260918064639` | `financial_settlement_notifications` | `20260917240000_financial_settlement_notifications.sql` |
| `20260918064645` | `consolidate_insurance_settlement_notifications` | `20260917241000_consolidate_insurance_settlement_notifications.sql` |
| `20260918064652` | `add_radiologist_role` | `20260918060000_add_radiologist_role.sql` |
| `20260918064659` | `staff_patient_notification_access_bridge` | `20260918070000_staff_patient_notification_access_bridge.sql` |
| `20260918072351` | `maternity_read_workspace` | `20260918100000_maternity_read_workspace.sql` |
| `20260918073627` | `pharmacy_read_workspace_security_bridge` | `20260918073000_pharmacy_read_workspace_security_bridge.sql` |
| `20260918073713` | `laboratory_read_workspace_security_bridge` | `20260918073500_laboratory_read_workspace_security_bridge.sql` |
| `20260918084852` | `emergency_read_workspace_security_bridge` | `20260918074000_emergency_read_workspace_security_bridge.sql` |
| `20260918085811` | `operational_workspace_security_bridge` | `20260918143000_operational_workspace_security_bridge.sql` |
| `20260918163526` | `optimize_remaining_auth_rls_initplans_20260918` | `20260918171000_optimize_remaining_auth_rls_initplans_20260918.sql` |
| `20260918164042` | `harden_service_order_actor_boundary_20260918` | `20260918170000_harden_service_order_actor_boundary_20260918.sql` |
| `20260918164759` | `optimize_service_order_event_rls_initplan_20260918` | `20260918172000_optimize_service_order_event_rls_initplan_20260918.sql` |
| `20260918221434` | `tighten_clinical_admission_anesthetic_rls_20260918` | `20260918173000_tighten_clinical_admission_anesthetic_rls_20260918.sql` |
| `20260918222218` | `bind_anesthetic_clearance_actor_20260918` | `20260918180000_bind_anesthetic_clearance_actor_20260918.sql` |
| `20260918222257` | `consolidate_overlapping_select_rls_20260918` | `20260918181500_consolidate_overlapping_select_rls_20260918.sql` |
| `20260919055443` | `align_admission_override_with_canonical_facility_configuration` | `20260919055741_align_admission_override_with_canonical_facility_configuration.sql` |
| `20260919060738` | `20260919061000_persist_service_release_authorization_metadata` | `20260919061000_persist_service_release_authorization_metadata.sql` |
| `20260919061518` | `20260919062000_scope_it_support_system_logs` | `20260919062000_scope_it_support_system_logs.sql` |
| `20260919062218` | `20260919063000_remove_direct_it_audit_log_select` | `20260919063000_remove_direct_it_audit_log_select.sql` |
| `20260919062524` | `20260919064000_scope_it_admin_notifications` | `20260919064000_scope_it_admin_notifications.sql` |
| `20260921051847` | `20260920061000_service_order_item_payment_release_hardening` | `20260920061000_service_order_item_payment_release_hardening.sql` |
| `20260921052113` | `20260920062000_insurance_claim_financial_bounds` | `20260920062000_insurance_claim_financial_bounds.sql` |
| `20260921052230` | `20260920063000_insurance_claim_transition_state_hardening` | `20260920063000_insurance_claim_transition_state_hardening.sql` |
| `20260921052236` | `20260920064000_invoice_item_payment_concurrency_hardening` | `20260920064000_invoice_item_payment_concurrency_hardening.sql` |
| `20260921052241` | `20260920065000_billable_item_materialization_concurrency_hardening` | `20260920065000_billable_item_materialization_concurrency_hardening.sql` |
| `20260921052316` | `20260920070000_discharge_claim_replay_hardening` | `20260920070000_discharge_claim_replay_hardening.sql` |
| `20260921052323` | `20260920071000_pharmacy_dispensing_quantity_hardening` | `20260920071000_pharmacy_dispensing_quantity_hardening.sql` |
| `20260921052328` | `20260920072000_pharmacy_pos_integrity_hardening` | `20260920072000_pharmacy_pos_integrity_hardening.sql` |
| `20260921052332` | `20260920073000_pharmacy_inventory_workspace_hardening` | `20260920073000_pharmacy_inventory_workspace_hardening.sql` |
| `20260921052337` | `20260920074000_pharmacy_dispense_consistency_hardening` | `20260920074000_pharmacy_dispense_consistency_hardening.sql` |
| `20260921052341` | `20260920075000_service_order_release_consistency_hardening` | `20260920075000_service_order_release_consistency_hardening.sql` |
| `20260921052426` | `20260920080000_lab_lifecycle_consistency_hardening` | `20260920080000_lab_lifecycle_consistency_hardening.sql` |
| `20260921052431` | `20260920081000_imaging_lifecycle_consistency_hardening` | `20260920081000_imaging_lifecycle_consistency_hardening.sql` |
| `20260921052434` | `20260920082000_procedure_mar_lifecycle_security_hardening` | `20260920082000_procedure_mar_lifecycle_security_hardening.sql` |
| `20260921052438` | `20260920083000_theatre_transfusion_lifecycle_consistency_hardening` | `20260920083000_theatre_transfusion_lifecycle_consistency_hardening.sql` |
| `20260921052442` | `20260920084000_referral_handover_lifecycle_consistency_hardening` | `20260920084000_referral_handover_lifecycle_consistency_hardening.sql` |
| `20260921052447` | `20260920085000_admission_discharge_replay_consistency_hardening` | `20260920085000_admission_discharge_replay_consistency_hardening.sql` |
| `20260921052451` | `20260920090000_emergency_transfusion_identity_state_hardening` | `20260920090000_emergency_transfusion_identity_state_hardening.sql` |
| `20260921052619` | `20260920093000_staff_directory_notification_least_privilege` | `20260920093000_staff_directory_notification_least_privilege.sql` |
| `20260921052623` | `20260920094000_maternity_workspace_read_consistency` | `20260920094000_maternity_workspace_read_consistency.sql` |
| `20260921052628` | `20260920095000_clinical_workspace_read_hardening` | `20260920095000_clinical_workspace_read_hardening.sql` |
| `20260921052632` | `20260920100000_operational_workspace_read_least_privilege` | `20260920100000_operational_workspace_read_least_privilege.sql` |
| `20260921052636` | `20260920101000_operational_workspace_module_reconciliation` | `20260920101000_operational_workspace_module_reconciliation.sql` |
| `20260921052640` | `20260920102000_admission_workspace_read_security` | `20260920102000_admission_workspace_read_security.sql` |
| `20260921052643` | `20260920103000_patient_admission_history_read_security` | `20260920103000_patient_admission_history_read_security.sql` |
| `20260921052659` | `20260920210000_remove_legacy_claim_transition_overloads` | `20260920210000_remove_legacy_claim_transition_overloads.sql` |
| `20260921052703` | `20260920211000_privileged_admin_resource_scope_hardening` | `20260920211000_privileged_admin_resource_scope_hardening.sql` |
| `20260921052707` | `20260920212000_retire_legacy_admin_role_rpc` | `20260920212000_retire_legacy_admin_role_rpc.sql` |
| `20260921052711` | `20260920220000_notification_queue_atomic_delivery` | `20260920220000_notification_queue_atomic_delivery.sql` |
| `20260921052715` | `20260920221000_ai_workspace_least_privilege` | `20260920221000_ai_workspace_least_privilege.sql` |
| `20260921052718` | `20260920222000_ai_protocol_lifecycle_hardening` | `20260920222000_ai_protocol_lifecycle_hardening.sql` |
| `20260921052722` | `20260920222100_ai_protocol_draft_creation` | `20260920222100_ai_protocol_draft_creation.sql` |
| `20260921052726` | `20260920223000_ai_clinical_context_read_scoped` | `20260920223000_ai_clinical_context_read_scoped.sql` |
| `20260921054344` | `clinical_read_context_linkage_hardening_clean` | `20260921100000_clinical_read_context_linkage_hardening_clean.sql` |
| `20260921055221` | `notification_queue_worker_auth_fix` | `20260921103000_notification_queue_worker_auth_fix.sql` |
| `20260921064730` | `post_merge_runtime_role_lookup_fix` | `20260921121000_post_merge_runtime_role_lookup_fix.sql` |
| `20260921085524` | `20260921090000_harden_ai_clinical_context_role_lookup` | `20260921090000_harden_ai_clinical_context_role_lookup.sql` |
| `20260922083045` | `operational_workspace_medication_read_minimization` | `20260922090000_operational_workspace_medication_read_minimization.sql` |
| `20260925150644` | `facility_notification_onboarding` | `20260925180000_facility_notification_onboarding.sql` |
| `20260925161337` | `notification_advisor_reconciliation` | `20260925192000_notification_advisor_reconciliation.sql` |
| `20260925161432` | `20260925150000_production_notification_module` | `20260925150000_production_notification_module.sql` |
| `20260925161435` | `20260925170000_notification_provider_operationalization` | `20260925170000_notification_provider_operationalization.sql` |
| `20260925161438` | `20260925181000_notification_queue_service_role_reconciliation` | `20260925181000_notification_queue_service_role_reconciliation.sql` |
| `20260925161441` | `20260925182000_notification_facility_onboarding_reconciliation` | `20260925182000_notification_facility_onboarding_reconciliation.sql` |
| `20260925161443` | `20260925183000_notification_smtp_provider` | `20260925183000_notification_smtp_provider.sql` |
| `20260925161446` | `20260925184000_notification_onboarding_configuration_catalog` | `20260925184000_notification_onboarding_configuration_catalog.sql` |
| `20260925161449` | `20260925190000_admin_it_notification_settings_control_plane` | `20260925190000_admin_it_notification_settings_control_plane.sql` |
| `20260925161522` | `notification_performance_reconciliation` | `20260925193000_notification_performance_reconciliation.sql` |
| `20260925161542` | `notification_facility_policy_finalization` | `20260925194000_notification_facility_policy_finalization.sql` |
| `20260925163034` | `notification_advisor_finalization` | `20260925200000_notification_advisor_finalization.sql` |
| `20260925205231` | `20260925195500_notification_provider_credentials` | `20260925195500_notification_provider_credentials.sql` |
| `20260925205248` | `20260925200000_notification_inbound_email_store` | `20260925200000_notification_inbound_email_store.sql` |
| `20260925210206` | `20260925202000_notification_provider_it_admin_multi_provider` | `20260925202000_notification_provider_it_admin_multi_provider.sql` |
| `20260925223450` | `20260925220000_notification_event_catalog_expansion` | `20260925220000_notification_event_catalog_expansion.sql` |
| `20260925230241` | `add_radiology_technician_role` | `20260925233000_add_radiology_technician_role.sql` |
| `20260925232926` | `20260925231500_harden_patient_admission_wrapper_execute` | `20260925231500_harden_patient_admission_wrapper_execute.sql` |
| `20260925232928` | `20260925240000_notification_internal_table_rls_guards` | `20260925240000_notification_internal_table_rls_guards.sql` |
| `20260925233744` | `seed_radiology_technician_permissions` | `20260925233500_seed_radiology_technician_permissions.sql` |
| `20260926000317` | `20260925234500_fix_facility_access_policy_execution_boundary` | `20260925234500_fix_facility_access_policy_execution_boundary.sql` |
| `20260926005923` | `20260926012000_governed_catalogue_creation_privileges` | `20260926012000_governed_catalogue_creation_privileges.sql` |
| `20260926005934` | `20260926012100_fix_catalogue_service_unit_default` | `20260926012100_fix_catalogue_service_unit_default.sql` |
| `20260926010444` | `20260926013000_fix_patient_bill_invoice_item_source_key` | `20260926013000_fix_patient_bill_invoice_item_source_key.sql` |
| `20260926225635` | `fix_pay_selected_no_conflict` | `20260926230000_fix_pay_selected_no_conflict.sql` |
| `20260926232847` | `role_dashboard_server_summary` | `20260926233000_role_dashboard_server_summary.sql` |
| `20260926235425` | `billing_window_insurance_credit_receipt` | `20260926223601_billing_window_insurance_credit_receipt.sql` |
| `20260927001253` | `dashboard_role_resolution_production_reconciliation` | `20260927001500_dashboard_role_resolution_production_reconciliation.sql` |
| `20260928124839` | `post_merge_runtime_patient_history_rpcs` | `20260921120000_post_merge_runtime_patient_history_rpcs.sql` |
| `20260928124849` | `harden_patient_hub_clinical_snapshot_roles` | `20260927073000_harden_patient_hub_clinical_snapshot_roles.sql` |
| `20260928171053` | `clinical_reference_values` | `20260928170000_clinical_reference_values.sql` |
| `20260928171108` | `harden_clinical_reference_audit_trigger` | `20260928171200_harden_clinical_reference_audit_trigger.sql` |
| `20260928172610` | `complete_triage_clinical_reference_coverage` | `20260928183000_complete_triage_clinical_reference_coverage.sql` |
| `20260928220742` | `add_bmi_clinical_reference` | `20260928210000_add_bmi_clinical_reference.sql` |
| `20260928234353` | `triage_offline_idempotency` | `20260928233000_triage_offline_idempotency.sql` |
| `20260929055007` | `triage_server_vital_requirement_parity` | `20260929060000_triage_server_vital_requirement_parity.sql` |
| `20260929055513` | `triage_offline_replay_race_safety` | `20260929062000_triage_offline_replay_race_safety.sql` |
| `20260929055841` | `ward_bed_facility_boundary` | `20260929070000_ward_bed_facility_boundary.sql` |
| `20260929061302` | `inpatient_facility_boundaries` | `20260929073000_inpatient_facility_boundaries.sql` |
| `20260929062036` | `ward_bed_management_control_plane` | `20260929080000_ward_bed_management_control_plane.sql` |
| `20260929062038` | `ward_management_facility_selection` | `20260929081500_ward_management_facility_selection.sql` |
| `20260929062043` | `ward_management_workspace_read_surface` | `20260929083000_ward_management_workspace_read_surface.sql` |
| `20260929062045` | `expand_department_service_creation_roles` | `20260929084500_expand_department_service_creation_roles.sql` |
| `20260929062047` | `20260929080000_ward_bed_management_control_plane` | `20260929080000_ward_bed_management_control_plane.sql` |
| `20260929062050` | `20260929081500_ward_management_facility_selection` | `20260929081500_ward_management_facility_selection.sql` |
| `20260929062053` | `20260929083000_ward_management_workspace_read_surface` | `20260929083000_ward_management_workspace_read_surface.sql` |
| `20260929062055` | `20260929084500_expand_department_service_creation_roles` | `20260929084500_expand_department_service_creation_roles.sql` |
| `20260929062248` | `harden_legacy_ward_visibility` | `20260929090000_harden_legacy_ward_visibility.sql` |
| `20260929062847` | `harden_ward_table_data_api_boundary` | `20260929100000_harden_ward_table_data_api_boundary.sql` |
| `20260929063050` | `harden_operational_workspace_search_path` | `20260929103000_harden_operational_workspace_search_path.sql` |
| `20260929063454` | `service_catalogue_department_control` | `20260929103000_service_catalogue_department_control.sql` |
| `20260929063458` | `insurance_tariff_governance` | `20260929110000_insurance_tariff_governance.sql` |
| `20260929063506` | `reconcile_billing_canonical_tariffs` | `20260929113000_reconcile_billing_canonical_tariffs.sql` |
| `20260929063756` | `insurance_company_master_data` | `20260929100000_insurance_company_master_data.sql` |
| `20260929063848` | `claim_reconciliation_read_context` | `20260929121500_claim_reconciliation_read_context.sql` |
| `20260929064521` | `claim_invoice_reconciliation` | `20260929120000_claim_invoice_reconciliation.sql` |
| `20260929081044` | `patient_canonical_insurer_linkage` | `20260929150000_patient_canonical_insurer_linkage.sql` |
| `20260929094721` | `canteen_dietary_operational_workspace` | `20260929150000_canteen_dietary_operational_workspace.sql` |
| `20260929094922` | `seed_patient_meal_menu_permission` | `20260929150500_seed_patient_meal_menu_permission.sql` |
| `20260929094950` | `enable_meal_menu_realtime` | `20260929151000_enable_meal_menu_realtime.sql` |
| `20260929095050` | `fix_canteen_realtime_topic_authorization` | `20260929151500_fix_canteen_realtime_topic_authorization.sql` |
| `20260929095149` | `restrict_canteen_patient_context_fields` | `20260929152000_restrict_canteen_patient_context_fields.sql` |
| `20260929095154` | `cover_unindexed_foreign_keys` | `20260929163000_cover_unindexed_foreign_keys.sql` |
| `20260929095507` | `harden_claim_security_definer_search_path` | `20260929164500_harden_claim_security_definer_search_path.sql` |
| `20260929100439` | `harden_clinical_security_definer_search_paths` | `20260929171500_harden_clinical_security_definer_search_paths.sql` |
| `20260929100626` | `role_dashboard_workflow_kpi_alignment` | `20260929170000_role_dashboard_workflow_kpi_alignment.sql` |
| `20260929100746` | `patient_workflow_field_authorization` | `20260929174500_patient_workflow_field_authorization.sql` |
| `20260929101100` | `harden_clinical_financial_security_definer_search_paths_batch2` | `20260929180000_harden_clinical_financial_security_definer_search_paths_batch2.sql` |
| `20260929101220` | `role_dashboard_radiologist_workflow_boundary` | `20260929190000_role_dashboard_radiologist_workflow_boundary.sql` |
| `20260929141826` | `role_dashboard_kpi_cleanup` | `20260929200000_role_dashboard_kpi_cleanup.sql` |
| `20260929141913` | `harden_security_definer_workflow_paths_batch3` | `20260929181500_harden_security_definer_workflow_paths_batch3.sql` |
| `20260929142135` | `harden_security_definer_workflow_paths_batch4` | `20260929183000_harden_security_definer_workflow_paths_batch4.sql` |
| `20260929142353` | `harden_security_definer_auth_helper_paths_batch5` | `20260929184500_harden_security_definer_auth_helper_paths_batch5.sql` |
| `20260929142436` | `active_dashboard_role_context` | `20260929203000_active_dashboard_role_context.sql` |
| `20260929143037` | `fix_canteen_menu_rbac_realtime` | `20260929200000_fix_canteen_menu_rbac_realtime.sql` |
| `20260929143830` | `harden_security_definer_read_workspace_paths_batch6` | `20260929203000_harden_security_definer_read_workspace_paths_batch6.sql` |
| `20260929144302` | `harden_security_definer_clinical_context_paths_batch7` | `20260929204500_harden_security_definer_clinical_context_paths_batch7.sql` |
| `20260929144949` | `20260929213000_harden_security_definer_mutation_paths_batch8` | `20260929213000_harden_security_definer_mutation_paths_batch8.sql` |
| `20260929145202` | `20260929214500_reconcile_revoked_role_helper_rls_policies` | `20260929214500_reconcile_revoked_role_helper_rls_policies.sql` |
| `20260929235557` | `account_reporting_lab_document_foundations` | `20260929233000_account_reporting_lab_document_foundations.sql` |
| `20260929235742` | `scope_reports_to_role_audiences` | `20260929234000_scope_reports_to_role_audiences.sql` |
| `20260930000158` | `seed_departmental_reporting_catalogue` | `20260929238000_seed_departmental_reporting_catalogue.sql` |
| `20260930011120` | `harden_department_queue_multirole` | `20260930012000_harden_department_queue_multirole.sql` |
| `20260930014945` | `complete_remaining_facility_attribution` | `20260930017000_complete_remaining_facility_attribution.sql` |
| `20260930101956` | `harden_facility_reconciliation_audit` | `20260930017200_harden_facility_reconciliation_audit.sql` |
| `20260930105425` | `derive_single_facility_context_for_users` | `20260930105508_derive_single_facility_context_for_users.sql` |
| `20260930110651` | `20260930111220_harden_facility_governance_rpc_privileges` | `20260930111220_harden_facility_governance_rpc_privileges.sql` |
| `20260930110653` | `20260930112000_global_diagnosis_catalogue_access` | `20260930112000_global_diagnosis_catalogue_access.sql` |
| `20260930110737` | `20260930112100_index_facility_sharing_audit_foreign_keys` | `20260930112100_index_facility_sharing_audit_foreign_keys.sql` |
| `20260930144000` | `expand_current_treatment_admin_access` | `20260930135600_expand_current_treatment_admin_access.sql` |
| `20260930160347` | `durable_medication_alert_acknowledgement` | `20260930152000_durable_medication_alert_acknowledgement.sql` |
| `20260930161253` | `harden_medication_alert_acknowledgement` | `20260930163000_harden_medication_alert_acknowledgement.sql` |
| `20260930163227` | `repair_start_appointment_encounter_facility_attribution` | `20260930170000_repair_start_appointment_encounter_facility_attribution.sql` |
| `20260930163749` | `fix_start_appointment_encounter_btrim` | `20260930170100_fix_start_appointment_encounter_btrim.sql` |
| `20261001163017` | `20261001173000_enable_test_role_mode` | `20261001173000_enable_test_role_mode.sql` |
| `20261001163101` | `20261001174500_test_mode_appointment_compatibility` | `20261001174500_test_mode_appointment_compatibility.sql` |
| `20261001163132` | `20261001175000_test_mode_production_default_off` | `20261001175000_test_mode_production_default_off.sql` |
| `20261001165327` | `super_admin_test_mode_toggle` | `20261001180000_super_admin_test_mode_toggle.sql` |
| `20261001200302` | `platform_superuser_facility_onboarding` | `20261001200000_platform_superuser_facility_onboarding.sql` |
| `20261001204413` | `fix_workflow_notification_role_enum_cast` | `20261001210000_fix_workflow_notification_role_enum_cast.sql` |
| `20261001213448` | `refresh_postgrest_patient_history_rpc_schema_cache` | `20261001163500_refresh_postgrest_patient_history_rpc_schema_cache.sql` |
| `20261001222653` | `clinical_results_production_tranche` | `20261001230000_clinical_results_production_tranche.sql` |
| `20261002050540` | `appointment_schedulable_patient_directory` | `20261002050200_appointment_schedulable_patient_directory.sql` |
| `20261002052916` | `scope_appointment_workflows_to_active_facility` | `20261002130000_scope_appointment_workflows_to_active_facility.sql` |
| `20261002054934` | `patient_hub_and_test_facility_context_repair` | `20261002160000_patient_hub_and_test_facility_context_repair.sql` |
| `20261002065556` | `allow_superadmin_facility_context_override` | `20261002070000_allow_superadmin_facility_context_override.sql` |
| `20261002065703` | `allow_superadmin_facility_context_override` | `20261002070000_allow_superadmin_facility_context_override.sql` |
| `20261002065912` | `superadmin_patient_history_context_access` | `20261002071000_superadmin_patient_history_context_access.sql` |
| `20261002070402` | `enforce_superadmin_selected_facility_reads` | `20261002072000_enforce_superadmin_selected_facility_reads.sql` |
| `20261002114059` | `20261002120000_pharmacy_inventory_catalogue_management` | `20261002120000_pharmacy_inventory_catalogue_management.sql` |
| `20261002114347` | `20261002124500_preserve_pharmacy_expiry_filter` | `20261002124500_preserve_pharmacy_expiry_filter.sql` |
| `20261002131200` | `pharmacy_global_catalogue_facility_stock_and_safety` | `20261002130000_pharmacy_global_catalogue_facility_stock_and_safety.sql` |
| `20261002131449` | `pharmacy_legacy_stock_reconciliation_rpc` | `20261002132000_pharmacy_legacy_stock_reconciliation_rpc.sql` |
| `20261002132256` | `pharmacy_global_category_edit` | `20261002132500_pharmacy_global_category_edit.sql` |
| `20261002134652` | `patient_hub_read_rpc_get_compatibility` | `20261002132500_patient_hub_read_rpc_get_compatibility.sql` |
| `20261002134656` | `reassert_start_appointment_encounter_facility_context` | `20261002180000_reassert_start_appointment_encounter_facility_context.sql` |
| `20261003094123` | `harden_service_order_and_invoice_facility_boundaries` | `20261003101500_harden_service_order_and_invoice_facility_boundaries.sql` |
| `20261003094747` | `harden_billing_workflow_facility_boundaries` | `20261003104000_harden_billing_workflow_facility_boundaries.sql` |
| `20261003094845` | `harden_insurance_claim_facility_boundaries` | `20261003111500_harden_insurance_claim_facility_boundaries.sql` |
| `20261004135725` | `20261004170000_make_test_control_rls_deny_explicit` | `20261004170000_make_test_control_rls_deny_explicit.sql` |
| `20261004184727` | `harden_notification_feature_flag_user_scope` | `20261004180000_harden_notification_feature_flag_user_scope.sql` |
| `20261004184838` | `refine_notification_feature_flag_admin_scope` | `20261004181000_refine_notification_feature_flag_admin_scope.sql` |
| `20261004185011` | `pin_create_ward_unit_wrapper_search_path` | `20261004183000_pin_create_ward_unit_wrapper_search_path.sql` |
| `20261004185307` | `harden_clinical_creation_facility_context` | `20261004184500_harden_clinical_creation_facility_context.sql` |
| `20261004185459` | `harden_appointment_inpatient_maternity_facility_context` | `20261004191500_harden_appointment_inpatient_maternity_facility_context.sql` |
| `20261004185636` | `pin_create_admission_workflow_search_path` | `20261004193000_pin_create_admission_workflow_search_path.sql` |
| `20261004185913` | `harden_remaining_clinical_workflows_v2` | `20261004200500_harden_remaining_clinical_workflows_v2.sql` |
| `20261004185957` | `correct_discharge_facility_assert_order` | `20261004201500_correct_discharge_facility_assert_order.sql` |
| `20261004190241` | `reconcile_legacy_test_patients_to_harmony_test_facility` | `20261004203000_reconcile_legacy_test_patients_to_harmony_test_facility.sql` |
| `20261004190639` | `harden_additional_clinical_patient_writes` | `20261004204500_harden_additional_clinical_patient_writes.sql` |
| `20261004190925` | `revoke_public_execute_hardened_clinical_rpcs` | `20261004205500_revoke_public_execute_hardened_clinical_rpcs.sql` |
| `20261004191059` | `optimize_medication_catalogue_rls_initplan` | `20261004211000_optimize_medication_catalogue_rls_initplan.sql` |
| `20261004192110` | `harden_collect_lab_sample_search_path` | `20261004212500_harden_collect_lab_sample_search_path.sql` |
| `20261004192252` | `harden_patient_hub_read_rpc_search_paths` | `20261004213500_harden_patient_hub_read_rpc_search_paths.sql` |
| `20261004192823` | `harden_billing_meal_patient_facility_context` | `20261004220000_harden_billing_meal_patient_facility_context.sql` |
| `20261004193017` | `pin_patient_journey_wrappers_search_path` | `20261004221500_pin_patient_journey_wrappers_search_path.sql` |
| `20261004193249` | `harden_direct_clinical_documentation_facility_context` | `20261004223000_harden_direct_clinical_documentation_facility_context.sql` |
| `20261004193458` | `harden_remaining_direct_patient_write_wrappers` | `20261004224000_harden_remaining_direct_patient_write_wrappers.sql` |
| `20261004193612` | `harden_care_transition_handover_lab_approval` | `20261004225000_harden_care_transition_handover_lab_approval.sql` |
| `20261004193700` | `pin_remaining_patient_ai_billing_wrappers` | `20261004231000_pin_remaining_patient_ai_billing_wrappers.sql` |
| `20261004193804` | `harden_alert_ack_and_ai_report_completion` | `20261004233000_harden_alert_ack_and_ai_report_completion.sql` |
| `20261004193947` | `harden_fertility_maternity_transfusion_theatre_workflows` | `20261004234000_harden_fertility_maternity_transfusion_theatre_workflows.sql` |
| `20261004194104` | `harden_ai_lab_patient_read_workflows` | `20261004240000_harden_ai_lab_patient_read_workflows.sql` |
| `20261004194159` | `harden_operational_workspace_read_boundaries` | `20261004241000_harden_operational_workspace_read_boundaries.sql` |
| `20261004194337` | `harden_referral_notification_insurance_reads` | `20261004242000_harden_referral_notification_insurance_reads.sql` |
| `20261004194525` | `harden_notification_consent_device_boundaries` | `20261004243000_harden_notification_consent_device_boundaries.sql` |
| `20261004194659` | `harden_remaining_notification_insurance_security_definer_boundaries` | `20261004244500_harden_remaining_notification_insurance_security_definer_boundaries.sql` |
| `20261004194845` | `harden_maternity_operational_workspace_search_paths` | `20261004250000_harden_maternity_operational_workspace_search_paths.sql` |
| `20261004201331` | `extend_encounter_submission_system_superuser` | `20261004254500_extend_encounter_submission_system_superuser.sql` |
| `20261004215532` | `align_platform_facility_compatibility_wrapper` | `20261004265500_align_platform_facility_compatibility_wrapper.sql` |
| `20261004224404` | `complete_platform_user_facility_membership_workflows` | `20261004273000_complete_platform_user_facility_membership_workflows.sql` |
| `20261004225608` | `complete_platform_user_role_assignment_workflow` | `20261004275000_complete_platform_user_role_assignment_workflow.sql` |
| `20261004231700` | `harden_bilateral_facility_data_sharing` | `20261004280000_harden_bilateral_facility_data_sharing.sql` |
| `20261004233801` | `20261004290000_restrict_user_active_facility_context_management` | `20261004290000_restrict_user_active_facility_context_management.sql` |
| `20261005091332` | `cleanup_inactive_user_facility_context` | `20261005091500_cleanup_inactive_user_facility_context.sql` |
| `20261005094757` | `align_operational_workspace_admin_roles` | `20261005090500_align_operational_workspace_admin_roles.sql` |
| `20261005100356` | `reconcile_workspace_role_resolution_and_zero_stock_edit` | `20261005110100_reconcile_workspace_role_resolution_and_zero_stock_edit.sql` |
| `20261005101014` | `reconcile_workspace_and_pharmacy_rpc_compatibility` | `20261005110000_reconcile_workspace_and_pharmacy_rpc_compatibility.sql` |
| `20261005101247` | `reconcile_inpatient_workspace_facility_boundaries` | `20261005110200_reconcile_inpatient_workspace_facility_boundaries.sql` |
| `20261005101316` | `remove_ambiguous_pharmacy_inventory_overloads` | `20261005110300_remove_ambiguous_pharmacy_inventory_overloads.sql` |
| `20261005102108` | `harden_patient_workflow_admin_roles` | `20261005110400_harden_patient_workflow_admin_roles.sql` |
| `20261005102543` | `harden_missing_foreign_key_indexes` | `20261005110500_harden_missing_foreign_key_indexes.sql` |
| `20261005120028` | `unify_runtime_patient_directory_and_pharmacy_zero_price_edits` | `20261005123000_unify_runtime_patient_directory_and_pharmacy_zero_price_edits.sql` |
| `20261005120259` | `allow_zero_price_pharmacy_creation` | `20261005123500_allow_zero_price_pharmacy_creation.sql` |
| `20261005152502` | `20261005153000_reconcile_authenticated_entrypoints_and_edge_schema_inventory` | `20261005153000_reconcile_authenticated_entrypoints_and_edge_schema_inventory.sql` |
| `20261006095729` | `patient_portal_self_service_runtime_reconciliation` | `20261006095000_patient_portal_self_service_runtime_reconciliation.sql` |
| `20261006144457` | `reconcile_platform_admin_workspace_context` | `20261006113000_reconcile_platform_admin_workspace_context.sql` |
| `20261006144500` | `revoke_anon_review_queue_security_definers` | `20261006120000_revoke_anon_review_queue_security_definers.sql` |
| `20261006152312` | `reconcile_remaining_facility_review_schema` | `20261006153000_reconcile_remaining_facility_review_schema.sql` |
| `20261007151221` | `patient_portal_identity_index` | `20261007161000_patient_portal_identity_index.sql` |
| `20261008132113` | `20261008120000_add_hr_payroll_foundation` | `20261008120000_add_hr_payroll_foundation.sql` |
| `20261008163616` | `patient_telemedicine_availability_reconciliation` | `20261008170000_patient_telemedicine_availability_reconciliation.sql` |
| `20261008213627` | `index_hr_payroll_foreign_keys` | `20261008214000_index_hr_payroll_foreign_keys.sql` |
| `20261013060634` | `laboratory_specimen_accession_and_rejection` | `20261012170000_laboratory_specimen_accession_and_rejection.sql` |

## 3. Hosted ledger entries with no matching current main filename

These 84 ledger entries have no same-name migration file in `main`. They require source recovery from Git history, the other branches, deployment artifacts, or verified SQL definitions.

| Hosted version | Hosted ledger name |
|---|---|
| `20260916002251` | `canonical_remote_schema` |
| `20260916003113` | `fix_start_imaging_order_queue_contract` |
| `20260916085626` | `reconcile_imaging_lifecycle_server_authority` |
| `20260916092730` | `reconcile_service_order_workflow_authority` |
| `20260916093000` | `harden_service_order_rpc_execute_boundary` |
| `20260916093154` | `reconcile_service_order_lifecycle_metadata` |
| `20260916093512` | `harden_selected_invoice_payment_service_release` |
| `20260916093546` | `complete_selected_invoice_service_order_release` |
| `20260916093817` | `allow_front_desk_payment_release_boundary` |
| `20260916103929` | `normalize_rls_auth_uid_initplans` |
| `20260916105824` | `harden_pharmacy_rpc_authorization_boundary` |
| `20260917113051` | `harden_reference_data_import_rpc_grants` |
| `20260917115211` | `add_migration_reconciliation_workflows` |
| `20260918064622` | `reconcile_transition_insurance_claim_canonical_signature` |
| `20260918065102` | `harden_public_security_definer_execute_boundary` |
| `20260918065144` | `remove_anon_security_definer_execute_grants` |
| `20260918065248` | `expand_staff_patient_read_authority` |
| `20260918065838` | `expand_is_clinical_staff_role_boundary` |
| `20260918084821` | `imaging_read_workspace_security_bridge` |
| `20260918090246` | `operational_workspace_nursing_care_extension` |
| `20260918090305` | `operational_workspace_reconcile_modules` |
| `20260918091121` | `operational_workspace_security_bridge_v2` |
| `20260918133547` | `add_it_admin_support_role_live` |
| `20260918133553` | `configure_it_admin_support_live` |
| `20260918133626` | `align_functional_domain_permissions_live` |
| `20260918152910` | `reconcile_missing_runtime_schemas_and_workflows_20260918` |
| `20260918152955` | `harden_reconciled_function_execute_privileges_20260918` |
| `20260918153045` | `revoke_explicit_public_function_grants_20260918` |
| `20260918153159` | `restore_missing_operational_rpc_workflows_20260918` |
| `20260918153526` | `restore_missing_patient_care_continuity_rpc_20260918` |
| `20260918153551` | `tighten_reconciled_rpc_execute_privileges_20260918` |
| `20260918153648` | `tighten_maternity_workspace_execute_privilege_20260918` |
| `20260918155629` | `reconcile_invoice_item_service_code_and_missing_tariff_workflow_20260918` |
| `20260918160533` | `reconcile_service_order_client_workflow_20260918` |
| `20260918161023` | `allow_admit_after_encounter_save_20260918` |
| `20260918161438` | `harden_billing_override_client_mutation_boundary_20260918` |
| `20260918161954` | `add_runtime_workflow_fk_indexes_20260918` |
| `20260918162153` | `scope_department_queue_workspace_20260918` |
| `20260918163330` | `add_remaining_runtime_fk_indexes_20260918` |
| `20260918164722` | `optimize_remaining_auth_rls_initplans_20260918b` |
| `20260921064954` | `patient_history_scoped_read_rpcs` |
| `20260925092357` | `scope_permission_rbac_policies_to_current_user` |
| `20260925145946` | `notification_multichannel_delivery` |
| `20260925150042` | `notification_external_fanout_reconciliation` |
| `20260925210150` | `20260925201500_notification_provider_multi_provider` |
| `20260926100909` | `facility_context_clinical_documentation_signatures` |
| `20260926101003` | `encounter_draft_and_facility_workspace` |
| `20260926101020` | `restore_operational_workspace_dispatcher` |
| `20260926101036` | `fix_operational_workspace_aggregate` |
| `20260926101334` | `lab_report_signature_resolution` |
| `20260926101400` | `lab_workspace_signature_projection` |
| `20260926235610` | `billing_window_rpc_reconcile_202609262359` |
| `20260927000209` | `triage_partial_measurement_nullability_20260927001000_v3` |
| `20260927000240` | `triage_temperature_precision_20260927002500` |
| `20260928135330` | `harden_patient_appointment_role_boundary` |
| `20260928140011` | `20260928163000_harden_legacy_clinical_role_boundaries` |
| `20260929154601` | `harden_radiology_patient_directory_search` |
| `20260929230239` | `20260929160000_harden_radiology_patient_directory_search` |
| `20260929230242` | `20260929170000_fix_ward_management_workspace_ordering` |
| `20260929230244` | `20260929200000_seed_system_settings_permission` |
| `20260929230247` | `20260929201000_allow_it_admin_notification_onboarding` |
| `20260929230250` | `20260929223000_harden_notification_config_anon_access` |
| `20261001165043` | `super_admin_test_mode_toggle_control` |
| `20261001222133` | `harden_workflow_notification_search_path` |
| `20261001222203` | `harden_workflow_notification_search_path_20261001220000` |
| `20261001222221` | `harden_workflow_notification_search_path_retry` |
| `20261001222235` | `harden_workflow_notification_enum_cast` |
| `20261001223220` | `normalize_notification_security_definer_search_path` |
| `20261004185953` | `harden_discharge_facility_context_v2` |
| `20261004191252` | `reassert_create_ward_unit_wrapper_search_path_v2` |
| `20261004200928` | `reconcile_encounter_draft_edit_workflow_live` |
| `20261004215044` | `restore_system_superuser_platform_access_and_facility_rpc_compatibility` |
| `20261005094733` | `harden_workspace_patient_directory_and_pharmacy_stock_editing` |
| `20261006094257` | `reconcile_patient_telemedicine_duty_validation` |
| `20261006094402` | `reconcile_patient_clinical_snapshot_facility_boundary_live` |
| `20261006094416` | `reconcile_patient_clinical_snapshot_facility_boundary_exact` |
| `20261006163711` | `reconcile_encounter_completion_billing_materialization_v2` |
| `20261013063118` | `create_laboratory_catalogue_parameters_reconciliation` |
| `20261013063129` | `create_lab_order_with_catalogue_atomic_reconciliation` |
| `20261026134619` | `reconcile_hr_payroll_record_management` |
| `20261026134818` | `reconcile_inpatient_reviews_seen_at` |
| `20261026135424` | `reconcile_laboratory_rpc_argument_contracts` |
| `20261026135602` | `reconcile_laboratory_rpc_legacy_schema_compatibility` |
| `20261026141054` | `reconcile_lab_catalogue_sample_quantity_rpc` |

## 4. Repeated migration names in the hosted ledger

The live ledger contains repeated names under different version identifiers. This may reflect migrations applied more than once under separate versions; do not delete or collapse these rows.

- `expand_master_data_migration_and_legacy_records`: `20260917112143`, `20260918064318`
- `add_reference_data_import_rpcs`: `20260917112203`, `20260918064331`
- `allow_superadmin_facility_context_override`: `20261002065556`, `20261002065703`

## 5. Candidate branch comparison

The branch `ci/future-proof-migration-contracts` has 659 SQL files and no duplicate timestamp groups in its migration directory. However, it has the same broad hosted-ledger alignment pattern: only 77 exact version/name matches, 256 same-name mappings with version differences, and 84 hosted entries without a same-name file. It also diverges significantly from `main` (327 commits ahead and 25 behind in the previously inspected comparison).

It is therefore useful as a source for reviewing collision repairs, but it is **not** a verified migration baseline and must not be merged wholesale.

The current `main` branch contains a later `20261024070000` migration than that candidate branch's migration directory, while the live ledger has five later October 26 entries not represented by current `main` filenames:
- `20261026134619_reconcile_hr_payroll_record_management`
- `20261026134818_reconcile_inpatient_reviews_seen_at`
- `20261026135424_reconcile_laboratory_rpc_argument_contracts`
- `20261026135602_reconcile_laboratory_rpc_legacy_schema_compatibility`
- `20261026141054_reconcile_lab_catalogue_sample_quantity_rpc`

These five should be recovered as exact SQL files from their deployment source or verified commit history. Do not recreate them from their names alone.

## 6. Live database security and schema-advisor observations

The public table inventory reports 156 tables, all 156 with RLS enabled. The live security advisor reports:
- **INFO — RLS Enabled No Policy:** 2 finding(s) (`rls_enabled_no_policy`)
- **WARN — Function Search Path Mutable:** 1 finding(s) (`function_search_path_mutable`)
- **WARN — Signed-In Users Can Execute SECURITY DEFINER Function:** 279 finding(s) (`authenticated_security_definer_function_executable`)
- **WARN — Leaked Password Protection Disabled:** 1 finding(s) (`auth_leaked_password_protection`)

Notable findings:
- 279 SECURITY DEFINER functions callable by the authenticated role. These may be legitimate workflow RPCs, but each function must be reviewed for explicit authentication, role authorization, tenant/facility scoping, safe search_path, and argument validation. Do not bulk-revoke execution without checking application dependencies.
- `public.ensure_updated_at` has a mutable search_path.
- `public.lab_test_group_items` and `public.lab_test_groups` have RLS enabled but no policies; verify whether these are intended to be service-only tables.
- Leaked-password protection is disabled in Auth.

Performance advisor:
- **INFO — Unindexed foreign keys:** 4 finding(s) (`unindexed_foreign_keys`)
- **WARN — Auth RLS Initialization Plan:** 4 finding(s) (`auth_rls_initplan`)
- **INFO — Unused Index:** 456 finding(s) (`unused_index`)
- **WARN — Multiple Permissive Policies:** 12 finding(s) (`multiple_permissive_policies`)
- **WARN — Duplicate Index:** 1 finding(s) (`duplicate_index`)

These are separate security/performance remediation workstreams; this migration reconciliation did not alter them.

## 7. Safe correction plan

1. Freeze migration renames/deletions and avoid merging candidate timestamp rewrites.
2. Recover exact SQL bodies for the 84 hosted-only identities and the five latest October 26 migrations.
3. For each of the 256 renamed/version-shifted mappings, retrieve original commit history and compare SQL checksums where possible. The current SQL file must not be assumed equivalent merely because its name matches.
4. For each duplicate timestamp group in `main`, establish which migration identity is recorded in each target database and which SQL body was applied. Do not resolve with automatic renumbering.
5. Build an authoritative manifest containing hosted version, hosted name, canonical repository path, SHA-256, applied environments, and verification evidence.
6. Restore missing historical files under their actual applied identities only after verifying exact contents; preserve existing applied files. If the schema needs correction, use a new forward-only migration greater than the latest confirmed ledger version (`20261026141054` at this inspection).
7. Validate from a clean database, upgrade representative existing databases, run database contracts, and compare schema objects, policies, grants, and functions.
8. Verify staging/non-production first. Production deployment must remain a separate approved and serialized action.

## 8. Future migration guardrail

A snapshot of all 417 hosted ledger version/name pairs is now committed at `supabase/migration-ledger-baseline.json`, captured on 2026-11-23. The CI forward-only guard validates that manifest and requires every newly added migration to sort after both the target branch's latest migration and the latest hosted ledger version, currently `20261026141054`. The guard also rejects edits, deletions, renames, and duplicate versions introduced by a pull request. Existing hosted-ledger entries are immutable; a later baseline refresh may only append newly verified live ledger entries, preserving every prior version/name pair exactly. This snapshot is a version/name baseline only; it does not contain original SQL checksums or prove historical SQL equivalence. Refresh it in a separate reviewed PR only after a verified migration deployment and read-back of the live ledger; do not append a migration to the manifest in the same PR that first introduces its SQL file.

## 9. Current gate status

| Gate | Status |
|---|---|
| Supabase connection and live ledger read | `PASS` |
| Live ledger vs main exact version/name parity | `BLOCKED` — 77/417 exact identities |
| Main duplicate migration versions | `BLOCKED` — 21 groups |
| Hosted migrations recoverable by filename in main | `BLOCKED` — 84 ledger entries lack a file |
| Candidate branch as canonical baseline | `BLOCKED` — still mismatched and heavily divergent |
| Local checkout parity | `UNVERIFIED` |
| Clean replay and upgrade tests | `NOT RUN` — must not treat static branch checks as database replay |
| Forward-only regression and PR guard | `PASS` — CI run 2777 passed regression, hosted-ledger ordering, and append-only manifest refresh checks |
| Existing static migration inventory contract | `BLOCKED` — 21 duplicate groups and one invalid entry |
| Clean database replay | `BLOCKED` — preflight rejected migration inventory; Supabase startup and replay were skipped |
| Production migration readiness | `BLOCKED` |

**No database migrations were applied during this inspection.** This is a read-only evidence report. The hosted migration ledger is now verified as readable, but full repository-to-database parity is not achieved.


## 10. Follow-up verification and newly confirmed security details (2026-11-23 10:33 UTC)

### CI workflow correction

The Quality workflow previously stopped after the migration inventory preflight, preventing unrelated application checks from running. The workflow now reports that legacy migration blocker with `continue-on-error: true`, while the dedicated Migration contract workflow remains a required, fail-closed gate for migration changes and clean replay.

- Quality run `8861` / `45156923702`: **PASS**. All 64 job steps completed successfully, including TypeScript typecheck, ESLint, operational and clinical contracts, authorization/security contracts, laboratory and HR/payroll contracts, production build, and GitHub Pages artifact integrity.
- The migration-identity step was reported separately and did not suppress the remaining Quality checks.
- Migration contract run `2780` / `45156923892`: **BLOCKED as expected**. Forward-only regression, ancestry/order enforcement, and parity failure-semantics tests passed. Static migration inventory still fails on the existing 21 duplicate timestamp groups and the single invalid `$(path)` artifact. Clean replay preflight stopped before Supabase startup; no replay or database test was run.

This separates application quality from migration-history readiness; it does not waive migration validation or make the migration chain merge-ready.

### Laboratory panel table privileges

A read-only catalog inspection confirmed that `public.lab_test_groups` and `public.lab_test_group_items` both have RLS enabled and no policies. Their original migration `20261013180000_laboratory_test_panels.sql` explicitly revoked all table privileges from `PUBLIC`, `anon`, and `authenticated`, and the application uses the scoped `get_laboratory_test_groups` / `save_laboratory_test_group` RPCs rather than direct table access.

The current live ACL nevertheless grants both `anon` and `authenticated` all listed table privileges, including `TRUNCATE`, `TRIGGER`, `REFERENCES`, and PostgreSQL 17 `MAINTAIN`, in addition to row-level DML privileges. Both tables currently contain zero rows. RLS does not replace table-level privilege controls, and in particular does not protect against `TRUNCATE` privileges. This is a **high-priority privilege-drift finding**: the original revocations have been superseded by a later grant. Reasserting the original least-privilege boundary with a new forward-only migration is the intended correction. It was not applied because the historical migration chain remains blocked and no clean non-production replay/upgrade validation is available in this session.

### Mutable trigger function search path

The live definition of `public.ensure_updated_at()` only sets `NEW.updated_at = now()` and returns `NEW`, but it has no fixed `search_path`. A minimal forward correction can use `ALTER FUNCTION public.ensure_updated_at() SET search_path = ''` without replacing the function body. This has not been applied pending the same forward-migration and replay controls.

### Unversioned SQL artifact investigation

The invalid `supabase/migrations/$(path)` file is a 3,416-byte SQL source file introduced in commit `e08b4f4b1d3c1b0587cda1d12b6bd65e6836c93b` on 2026-10-01. It has no 14-digit migration version and therefore is not a valid Supabase migration identity. Its `create_workflow_notification` function body is older and materially differs from the live definition, which includes category-specific recipient authorization. It must not be renamed into a new migration or replayed as-is. It remains preserved pending a reviewed archival/removal decision.

### Updated state

- Application Quality and build: `PASS` (run 8861).
- Forward-only migration governance tests: `PASS` (run 2780).
- Migration inventory / clean replay: `BLOCKED` (21 duplicate timestamp groups plus the invalid unversioned artifact).
- Hosted ledger identity reconciliation: still `BLOCKED` (77 exact identities; 256 same-name timestamp mismatches; 84 hosted entries without a matching main filename).
- Production security remediation for lab panel grants and `ensure_updated_at`: `PENDING` — correction SQL identified, not applied.
- Local checkout parity: `UNVERIFIED`.
- Production migration readiness: `BLOCKED`.

No production database DDL was executed during this follow-up.


## 11. Forward-only security correction staged for review (2026-11-23)

A new migration was added to the draft PR:

`supabase/migrations/20261123090000_harden_laboratory_panel_table_privileges_and_timestamp_trigger.sql`

It is newer than the latest verified hosted migration version (`20261026141054`) and does not alter any historical migration. It performs only these targeted corrections:

1. Revokes table-level privileges from `PUBLIC`, `anon`, and `authenticated` on `public.lab_test_groups` and `public.lab_test_group_items`, preserving the existing owner and `service_role` privileges.
2. Sets `public.ensure_updated_at()` to `search_path = ''`.

Before staging, the live database catalog was checked again:
- Both laboratory panel tables currently grant broad privileges to `anon` and `authenticated`, including `TRUNCATE` and `MAINTAIN`.
- The two application RPCs, `get_laboratory_test_groups(boolean)` and `save_laboratory_test_group(uuid,text,text,text,numeric,uuid[],boolean)`, are SECURITY DEFINER functions owned by `postgres` and already have an empty search_path. This supports retaining the service/RPC access model while removing direct table grants.
- `ensure_updated_at()` is a non-SECURITY-DEFINER trigger function owned by `postgres`; its body only assigns `NEW.updated_at = now()` and returns `NEW`.

**Important:** this migration is staged in the PR only. It has not been applied to Supabase. CI must validate it, and the historical migration identity/replay blocker must be resolved before any deployment. It must not be used to bypass clean replay or upgrade validation.


## 12. CI result for staged security migration (2026-11-23)

- Quality run `8864` / `45157977971`: **PASS** — all 64 steps completed successfully, including typecheck, lint, application authorization/security contracts, production build, SPA route preparation, and Pages artifact integrity.
- Migration contract run `2783` / `45157978146`: forward-only regression, hosted-ledger ordering, and validation failure-semantics checks **PASS**. The historical inventory validation still **FAILS** on the pre-existing duplicate/invalid migration inventory. Clean replay was stopped at preflight; Supabase services were not started and the new security migration was not replayed.
- The 279 authenticated SECURITY DEFINER advisor warnings were examined further with a read-only catalog scan. 250 definitions contain one or more obvious authorization/facility guard patterns; 29 do not contain the scanned marker patterns. This is only a triage heuristic, not proof that the 29 functions are exploitable or that the other 250 are safe. No EXECUTE grants were changed. Each candidate requires source review and role/facility boundary tests before changing privileges.
- Performance findings remain unmodified: 4 unindexed foreign-key findings, 12 multiple-permissive-policy findings, 1 duplicate index finding, 456 unused-index notices, and 4 RLS initialization-plan notices. Unused-index notices are not sufficient evidence for dropping indexes; production workload and query plans are required.
- The security advisor still reports the two laboratory tables as RLS-enabled without policies. Their direct grants are staged for revocation; RLS no-policy findings can remain informational when access is intentionally restricted to SECURITY DEFINER RPCs. Verify the RPC execution path in clean replay before deployment.
- Leaked-password protection remains a dashboard/Auth configuration item and was not changed.

No production DDL or Auth settings were changed. PR #444 remains draft and blocked by historical migration identity recovery and clean replay.


## 13. Follow-up: regression guard and deeper SECURITY DEFINER triage (2026-11-23)

### Laboratory panel migration guard
Added `scripts/laboratory-panel-privilege-migration-contract.mjs` and wired it into `npm run test:migration-parity`. The test asserts that the staged migration:
- Revokes all direct table privileges from `PUBLIC`, `anon`, and `authenticated` on both laboratory panel tables.
- Pins `public.ensure_updated_at()` to an empty `search_path`.
- Does not add a new grant to client roles.

Migration contract run `2785` / `45158748458` confirms all three static migration/parity regression checks pass, including this new guard. It then fails at the expected historical inventory gate. The exact blockers remain the invalid `$(path)` entry and the 21 duplicate timestamp groups. The database replay job stops before starting Supabase. Thus, this proves the new migration's intended text contract only; it does not prove replay correctness or live behavior.

### Further review of advisor candidates
Read-only source inspection of sensitive functions found explicit checks in the sampled functions:
- `platform_set_user_role`: authentication, admin role, self-change prevention, platform-role restriction, and target facility membership checks.
- `platform_create_facility` / `platform_list_facilities`: explicit system-superuser checks.
- `get_patient_portal_medical_record`, `get_patient_invoice_summary`, and `get_patient_portal_video_sessions`: authenticated patient-to-user/email ownership checks.
- `get_patient_admission_history`: clinical/platform role check plus patient facility-context assertion.
- Laboratory catalogue creation wrappers call a helper that checks authenticated catalogue-creation permissions.
- `set_hms_test_runtime`: explicit system-superuser check, reason requirement, and test-environment-only guard.

These source samples do not clear the entire 279-function inventory. Remaining candidates require function-by-function review, especially helper functions and functions that rely on `profiles.role` rather than `user_roles`. No function EXECUTE privileges were changed.

### Dependency audit signal
The migration workflow's `npm ci` reported **29 dependency vulnerabilities (18 moderate, 11 high)**. No automatic `npm audit fix` or force upgrade was run because that could introduce incompatible dependency changes. The exact affected package paths and patched versions still need a dependency audit report and controlled lockfile update.

### Historical recovery attempts
Searched commit history for the five unrecovered hosted migration identities and checked the migration-reconciliation branch. No exact source files or matching commits were found. The `test/laboratory-migration-chain-reconciliation` branch is diverged (8 commits ahead, 36 behind `main`) and changes other migrations; it is not a safe source to merge. No SQL was reconstructed from filenames or guessed.

The report remains: application quality checks are green when the current run completes; the historical migration chain and production deployment are still blocked. No production DDL or Auth configuration changes were made.


### Final CI confirmation for this follow-up
- Quality run `8866` / `45158748492`: **PASS**, including all 64 steps and GitHub Pages artifact verification.
- Migration contract run `2785` / `45158748458`: static parity checks **PASS**, including the new laboratory panel migration guard; full migration identity validation **FAILS** on the known legacy inventory blockers; clean replay **NOT RUN**.



## 14. Historical source recovery update (2026-11-23)

Two of the five recent hosted migration identities previously reported as having no repository source have now been recovered from the historical repair branch `fix/missing-ai-diagnosis-schema-migration` (PR #437). Their SQL is preserved byte-for-byte as inactive `.candidate` artifacts under `docs/engineering/migration-source-candidates/`, not in the active `supabase/migrations/` directory:

- `20261026134619_reconcile_hr_payroll_record_management.sql` — source Git blob `a5e0c71da2de1dbae8634916c42156848344c312`.
- `20261026134818_reconcile_inpatient_reviews_seen_at.sql` — source Git blob `a31a95aeedcba05cd2d1876966278753f1b1d30b`.

The candidate filenames preserve the exact version/name identities recorded by the hosted migration ledger. They are provenance candidates only; they do not modify the hosted database or active migration chain. The source branch's PR description records that the HR/payroll and inpatient reconciliation work was applied to the connected Supabase project, but independent SQL-content equivalence against the original deployed migration payload is not available from the ledger and remains subject to source/provenance review. They were moved out of `supabase/migrations/` after CI correctly rejected them as historical additions older than the hosted latest version.

Three hosted migration identities still need exact source recovery:

- `20261026135424_reconcile_laboratory_rpc_argument_contracts`
- `20261026135602_reconcile_laboratory_rpc_legacy_schema_compatibility`
- `20261026141054_reconcile_lab_catalogue_sample_quantity_rpc`

PR #437 contains same-name laboratory candidates at different versions (`20261026140000_reconcile_laboratory_rpc_argument_contracts.sql` and `20261026150000_reconcile_lab_catalogue_sample_quantity_rpc.sql`). These are useful provenance leads, not exact identity matches; they have not been copied or renumbered. An earlier laboratory API compatibility migration is also not proof of the missing `20261026135602` source.

### Validation after source restoration

The two exact-version source files have been committed to the draft reconciliation branch. The resulting CI run must validate migration identity inventory, then clean replay. Until those checks pass, the restored files are not considered replay-verified and no production migration apply is authorized. The 21 duplicate-version groups and unversioned `$(path)` artifact remain separate blockers; the local working tree is still unverified.


## 15. Local checkout ZIP audit (2026-11-23)

The user supplied `harmony-health-hub.zip`. It was inspected as a local project snapshot; it contains no `.git` directory or Git history, so it cannot establish which local SQL versions were deployed or recover historical commits.

### Local migration inventory

- SQL migration files: **651**.
- Distinct 14-digit version prefixes: **628**.
- Duplicate version groups: **21**.
- Every duplicate group contains non-identical SQL contents (SHA-256 differs); these are not safe duplicate-file deletions.
- First filename-uniqueness test failure reproduced locally with Node 22: `20260912003000_phase2_pharmacy_procedure_imaging_gates.sql` and `20260912003000_phase4_triage.sql` share a version.
- Latest local SQL version: `20261024070000`.
- An additional unversioned file exists at `supabase/migrations/$(path)` (3,478 bytes; SHA-256 `b5127cd9d83e6988774b3345755451d9bc41d86dd1a7c9595223b69d90519e73`). It is not a valid timestamped SQL migration.
- The archive's `supabase-migration-list.txt` is UTF-16 and has a blank remote-version column; it is not evidence of a successful remote ledger comparison.

The hosted database ledger independently reports 417 unique entries, latest `20261026141054`. The local snapshot therefore trails the hosted latest version by two calendar days and does not contain any of the five exact 2026-10-26 hosted source files.

### Local snapshot is behind the reconciliation PR

The ZIP does not contain the current PR's `supabase/migration-ledger-baseline.json`, forward-only governance scripts, laboratory migration static guard, the two restored exact hosted migrations, or the staged laboratory security correction. This confirms that the uploaded local snapshot is not the current PR #444 working tree.

### Decision

No duplicate migration was renamed, deleted, merged, or rewritten. The duplicate files contain distinct SQL and their deployment status cannot be proven without Git history or an authoritative migration ledger snapshot. The unversioned `$(path)` artifact is preserved; its archival/removal must be reviewed separately. The correct next step remains to obtain the authoritative source history for the pre-baseline migrations and validate the canonical baseline/replay strategy, not to renumber files speculatively.

The local inventory check reproduced the existing migration filename uniqueness failure. Clean replay was not attempted because preflight fails. No local archive changes were made to the user's original ZIP and no production database changes were made.


## 16. Review of historical duplicate-repair candidate PR #437 (2026-11-23)

PR #437 branch `fix/missing-ai-diagnosis-schema-migration` was evaluated as a candidate source for the 21 duplicate-version groups and invalid artifact. It is **not safe to merge wholesale**: comparison against `main` shows the branch is 263 commits ahead and 9 behind, with broad migration and workflow changes. Its latest PR description still does not claim a successful full clean replay; it records the production baseline as unreconciled and production push disabled.

### Duplicate version evidence

The candidate branch's local migration register contains 661 SQL files with 661 unique 14-digit versions and no `$(path)` artifact. Its 23 collision repairs are useful as a mapping candidate. A comparison of the 22 ordinary old/new filename pairs against `main` and the live hosted ledger found:

- All 22 original duplicate version prefixes are absent from the current hosted ledger.
- All 22 proposed replacement version prefixes are also absent from the current hosted ledger.
- 17 of the 22 candidate renames are byte-identical Git blobs.
- 5 of the 22 candidate rename files have changed SQL contents.
- The additional `20260929200000_secure_default_function_execute_privileges.sql` to `20260929200002_secure_default_function_execute_privileges.sql` candidate also changes SQL contents (old/new Git blob SHAs differ).

Thus the repair branch demonstrates a collision-free filename plan, but it is not a pure rename-only patch. The 6 changed-content candidates must be reviewed separately. The absent versions in the one linked production ledger are evidence only for project `ygqoptvezotdqhtimdkr`; they do not prove that another shared environment never applied them. Even a version absent from production remains a local pending migration if added to the active migration directory.

### Provenance inventory from PR #437

Its candidate-only inventory (snapshot 2026-11-02, commit `31645d93d07fd620c3e7c54df9907ce239b3ebaf`) reports 661 local files and 417 hosted ledger entries: 80 shared version prefixes, 581 local-only versions, 337 remote-only versions, 257 same-name candidates without SQL equivalence proof, one ambiguous same-name candidate, and 79 remote entries with no same-name candidate. This is a candidate map, not a reconciled migration history.

The three remaining recent hosted laboratory sources are still unresolved:
- `20261026135424_reconcile_laboratory_rpc_argument_contracts` has a same-name candidate at version `20261026140000`.
- `20261026135602_reconcile_laboratory_rpc_legacy_schema_compatibility` has no candidate in that inventory.
- `20261026141054_reconcile_lab_catalogue_sample_quantity_rpc` has a same-name candidate at version `20261026150000`.

The candidate SQL for the 20261026140000 file combines multiple compatibility changes, so it cannot be treated as proof of the two separately recorded hosted migration payloads. The 20261026150000 candidate defines the sample-quantity RPC but is still only a same-name candidate; exact deployed SQL/checksum is not exposed by the version/name ledger.

### Decision

Do not merge PR #437 wholesale and do not copy its six changed-content rename candidates as historical truth. A focused historical repair could use the 17 byte-identical rename candidates only after confirming no other shared environment applied the old versions, and after explicitly keeping production apply blocked (the new local versions would otherwise be pending). The remaining six collision resolutions require source-level review. The current PR #444 remains forward-only; no historical rename has been made in it.


## 17. Read-only live laboratory candidate comparison (2026-11-23)

The live catalog was queried read-only to compare the same-name candidate SQL in PR #437 with deployed laboratory RPC/schema state.

Observed live function signatures and definitions:
- `get_laboratory_test_groups(boolean)`
- `save_laboratory_test_group(uuid,text,text,text,numeric,uuid[],boolean)`
- `get_lab_result_attachments(uuid[])`
- `create_lab_test_catalogue_item_with_sample_quantity(text,text,text,text,text,text,numeric,numeric,text,numeric,integer,jsonb)`

The live `pg_get_functiondef` output for these functions matches the corresponding function bodies shown in PR #437 candidate migrations `20261026140000_reconcile_laboratory_rpc_argument_contracts.sql` and `20261026150000_reconcile_lab_catalogue_sample_quantity_rpc.sql`, including SECURITY DEFINER execution and empty search_path. The live catalog also contains the canonical/legacy laboratory panel columns referenced by the candidate (including `group_name`/ `name`, `group_id`/ `lab_test_group_id`, `test_id`/ `test_catalogue_id`, and `display_order`/ `sort_order`), and `lab_test_catalogue.sample_quantity` is `text`.

This strengthens confidence that the candidate RPC definitions represent deployed behavior. It does **not** prove the entire candidate migration files are byte-identical to the original SQL recorded under hosted versions `20261026135424`, `20261026135602`, or `20261026141054`. In particular, no original source for the separate legacy-compatibility version `20261026135602` was found. The candidates remain provenance evidence only; no source file was copied, renumbered, or replayed from this comparison.


## 18. Historical candidate placement and CI contract correction (2026-11-23)

The two recovered recent SQL files were initially placed under `supabase/migrations/`. The forward-only contract correctly rejected them because their versions (`20261026134619` and `20261026134818`) are earlier than the hosted latest (`20261026141054`); adding them as new active migrations would violate the forward-only rule and could create an unsafe pending migration queue.

They have therefore been moved byte-for-byte to inactive provenance artifacts:
- `docs/engineering/migration-source-candidates/20261026134619_reconcile_hr_payroll_record_management.sql.candidate`
- `docs/engineering/migration-source-candidates/20261026134818_reconcile_inpatient_reviews_seen_at.sql.candidate`

They are not active Supabase migrations and must not be copied back into `supabase/migrations/` until an approved historical provenance reconciliation establishes their role in clean replay. The forward-only contract remains unchanged; the latest CI run is being used to confirm that this correction clears the two historical-addition errors while preserving the existing inventory preflight blockers.


## 19. CI after moving historical candidates out of active migrations (2026-11-23)

On PR head `cd761a0526388e147d9f740020c674901d6b33a9`:
- Migration contract run #2795 / `45175196230`: forward-only regression passed; forward-only migration contract passed with exactly one valid new forward migration; migration parity, workflow-regression, and laboratory privilege static guards passed. The subsequent full migration identity contract still fails only on the known invalid `$(path)` artifact and the 21 duplicate-version groups. Clean database replay was not started.
- The two historical source additions no longer trigger the forward-only contract. Their candidate copies remain outside the active migration directory.
- Quality run #8876 / `45175196173` was still in progress at the time of this report update; no conclusion is claimed.


## 20. Invalid artifact archived; duplicate-only preflight remains (2026-11-23)

The unversioned `supabase/migrations/$(path)` file has now been removed from the active migration directory and preserved byte-for-byte as `docs/engineering/migration-source-candidates/legacy-workflow-notification.sql.candidate`. Its original Git blob is `c5293005a039b1f370fe5a88932de1831aa8acc9`. It is not a valid 14-digit migration and was never a ledger entry.

The forward-only contract permits this single retirement only when the original blob from the PR base is identical to the archived candidate blob in HEAD. Regression coverage verifies the exact-copy case passes and a changed/tampered archive fails. All other existing migration deletions remain rejected.

CI on PR head `b40f9aaa8c31b1cfa4a11ba36c51191ed0910fa3`, Migration contract run #2799 / `45175510139`:
- Forward-only regression passed, including the new byte-identical archival case.
- Forward-only migration contract passed; one valid forward migration was added and the one invalid unversioned artifact was retired under the narrow archival exception.
- Migration parity regression and laboratory panel privilege static guard passed.
- Full migration identity validation now reports **only the 21 duplicate version groups**; the invalid `$(path)` error is gone.
- Clean replay still stops at preflight because of those duplicate versions; Supabase services were not started.

Quality run #8880 / `45175509954` remained in progress at report time. No production DDL or migration ledger changes were made.


### Latest head validation

On PR head `168856c9fd74b122f75b34d4f2b2e472f5caa1b1`:
- Quality run #8881 / `45175651558`: **PASS**.
- Migration contract run #2800 / `45175651574`: **FAIL at migration identity preflight only**. The invalid unversioned artifact is no longer reported; all 21 duplicate version groups remain. The clean replay job stopped before Supabase services started.

## 21. Latest migration gate and live advisor recheck (2026-11-23 13:24 UTC)

- Migration contract run #2801 (workflow run ID 45175937743) failed in both the clean replay preflight and schema/security contract jobs at the migration identity inventory step.
- The exact reported blocker is the same 21 duplicate migration version groups listed in section 1. The unversioned `$(path)` artifact is no longer reported.
- Forward-only regression, PR immutability/ordering checks, npm install, and migration validation failure-semantics checks passed before the inventory gate. The local Supabase CLI setup, service startup, replay, and post-replay schema checks were skipped because preflight correctly failed closed.
- Quality run #8882 passed. This is independent of migration-chain replay and does not establish replay readiness.
- A fresh read-only Supabase Security Advisor scan observed two RLS-enabled laboratory tables without policies (`public.lab_test_groups`, `public.lab_test_group_items`), one mutable search_path warning for `public.ensure_updated_at()`, 279 authenticated SECURITY DEFINER execute warnings, and leaked-password protection disabled. The two lab tables' no-policy state is consistent with the staged direct-table privilege revocation strategy, but the staged migration remains unapplied; no advisor warning was auto-fixed.
- The linked Supabase project's development-branch listing is empty. This does not establish whether the owner has other separate Supabase projects or environments.
- Hosted migration ledger remains 417 rows / 417 distinct versions, latest `20261026141054`; the five late-October reconciliation entries remain present.
- Historical duplicate-version renames remain blocked pending confirmation that no other shared Supabase environments have applied these versions and a complete cross-environment ledger check. No migration SQL was renumbered, no production DDL was applied, and the draft PR was not merged.


## 22. Environment clarification and latest CI (2026-11-23)

The project owner clarified that the development environment they are aware of predates the introduction of Supabase. It is therefore a legacy pre-Supabase development environment, not a known additional Supabase migration ledger. The linked Supabase account exposes the single known project `harmony-health-hub`; its development-branch list is empty. This is recorded as owner-reported scope, not proof that no other unconnected Supabase project exists.

The known pre-Supabase environment does not authorize historical migration renames: its schema/deployment history has not been provided, and any renamed migration may be interpreted as pending by the current hosted project. The 23 PR #437 collision-repair candidates therefore remain unpromoted. The 17 byte-identical candidate renames and six content-changing candidates require separate provenance and replay analysis; no rename is being treated as a safe production migration.

Latest CI on PR head `63fe0ce7a1e923d6e244e65fdd3117e5b77ac7a1`:
- Quality run #8883 passed.
- Migration contract run #2802 failed at the migration identity inventory step. The forward-only regression and immutability/ordering checks passed.
- The clean replay job stopped before Supabase services started because the 21 duplicate version groups remain. No clean replay or post-replay schema verification occurred.
- No production DDL or migration-ledger changes were made; PR #444 remains draft.


## 23. Hosted ledger snapshot parity revalidation (2026-11-23)

A fresh read-only Supabase migration-list query was compared against the committed `supabase/migration-ledger-baseline.json` snapshot on this branch.

- Snapshot SHA: `3fd761783ac36ad12473afd8cd15b93bea74c838`.
- Snapshot and live ledger each contain 417 migration version/name entries.
- All 417 version/name pairs match exactly; no missing, extra, or changed entries were found.
- The earliest live entry remains `20260916002251 canonical_remote_schema`; the latest remains `20261026141054 reconcile_lab_catalogue_sample_quantity_rpc`.
- This verifies the committed snapshot against the linked hosted ledger at the time of this read-only check. It does not recover the original SQL payloads, prove SQL equivalence, or resolve the 21 duplicate local migration-version groups.

The latest PR #444 head remains `1f9a5c926c0d09817526eae64078a08f348df01a` at the time of this check. Quality run #8886 passed; migration-contract run #2805 failed at duplicate-version identity preflight. Clean replay and post-replay schema verification did not run. No production DDL or migration-ledger changes were made.


## 24. Migration-candidate branch and latest CI recheck (2026-11-23)

A further repository search checked the imaging-related branches and the known migration-reconciliation branches for the two September baseline SQL files and the three unrecovered late-October laboratory SQL files. None of the checked branches contained those exact source paths. This is a bounded branch/path search, not proof that no recoverable copy exists elsewhere (for example, in an unindexed artifact or external backup).

The historical repair work in PR #442 (`integration/migration-reconciliation`, head `a95596b0490345160ca10353bd3841742a77cedd`) and PR #437 remains candidate evidence only. PR #442 documents a 23-file collision normalization and earlier clean-replay fixes, but it is an older, separate integration branch, remains draft/open and non-mergeable, and its own recorded clean-replay history contains unresolved blockers. Its renames and changed SQL are not promoted into this branch without a fresh source/provenance review and clean replay.

Latest PR #444 CI on head `88c3bd696d4e38b0986a14afd2fc9fda0498cca0`:
- Quality run #8887: passed.
- Migration contract run #2806: failed in both migration preflight jobs at the same 21 duplicate migration-version groups. The validator stops before Supabase CLI setup, local database startup, clean replay, and schema/RPC/privilege/RLS verification.
- Vercel status: success (preview/deployment check only; not a database replay result).

The exact duplicate groups are unchanged from the inventory already recorded in section 21. No duplicate was renamed or deleted in this continuation. No production SQL, migration history, or schema was changed. PR #444 remains draft and must not merge until source reconciliation, duplicate resolution, clean replay, and post-replay verification pass on the same head.


## 25. Exact duplicate preflight diagnostics and PR #442 collision candidate review (2026-11-23 14:53 UTC)

The latest PR #444 head `76cb6d08e0d034403befba7583a00363f8e2b012` triggered Migration contract run #2807 (workflow run ID `45199018700`). The Quality workflow #8888 passed; migration contract failed.

The two migration-contract jobs both stop at the identity validation stage. The clean replay job reports the 21 duplicate version groups listed in section 1; Supabase CLI setup, local Supabase startup, full migration replay, and post-replay schema/RPC/privilege/RLS verification are skipped. The schema/security contract job passes its forward-only regression, immutable-history/ordering checks, npm installation, and migration validation failure-semantics checks, then fails at the same migration identity inventory gate.

The exact 21 duplicate prefixes reported by the clean replay job are:

`20260912003000`, `20260912010000`, `20260912021000`, `20260912024500`, `20260912162000`, `20260912200000`, `20260912250000`, `20260913180000`, `20260914140000`, `20260914150000`, `20260914170000`, `20260915170000`, `20260925200000`, `20260929100000`, `20260929103000`, `20260929150000`, `20260929200000`, `20260929203000`, `20260930012000`, `20261002130000`, and `20261002132500`.

PR #442's current metadata describes a 23-file collision-normalization tranche (20 content-identical rename claims and three changed-content repairs). Its changed-file review shows it is not a collision-only patch: it also adds/restores schema prerequisites, changes compatibility and authorization SQL, adjusts RLS policies, and introduces other forward candidates. The PR remains draft and non-mergeable, and its baseline is explicitly marked unreconciled with production push disabled. Its description and candidate filenames are not sufficient proof that the exact source SQL and intended order are correct for this branch. No PR #442 migration was copied, renamed, or promoted.

The next safe resolution step is a narrow per-collision provenance matrix: compare each old file's Git blob and full SQL body with the proposed replacement, identify whether either version appears in any known environment's ledger, determine the intended execution order and dependencies, and replay the resulting complete chain on a clean disposable database. Changed-content candidates require SQL review and tests, not rename treatment. The two missing September baseline sources and three unrecovered late-October laboratory sources remain independent blockers to declaring clean replay complete.

No migration file was renamed or deleted in this continuation. No production SQL, schema, or migration ledger was changed. PR #444 remains draft and must not merge.


## 26. PR #442 collision candidate diff classification (2026-11-23)

A fresh GitHub compare of `main` against `integration/migration-reconciliation` (PR #442) was used to classify the candidate collision repair by actual file history, rather than relying only on the PR description.

### Rename-classified candidates

Git's compare endpoint identifies 20 migration renames. Seventeen have zero additions and zero deletions in the compare result, consistent with byte-identical content-preserving renames. Three are not pure renames:

| Original path | Candidate path | Diff evidence |
|---|---|---|
| `20260912024500_global_hims_inpatient_emergency_theatre_insurance.sql` | `20260912024501_global_hims_inpatient_emergency_theatre_insurance.sql` | 167 additions |
| `20260912200000_prescription_payment_lifecycle_reconciliation.sql` | `20260912200001_prescription_payment_lifecycle_reconciliation.sql` | 5 additions |
| `20260914170000_clinical_triage_medication_mutation_hardening.sql` | `20260914170001_clinical_triage_medication_mutation_hardening.sql` | 2 additions, 2 deletions |

The 17 zero-diff rename candidates are:

- `20260912003000_phase4_triage.sql` → `20260912003500_phase4_triage.sql`
- `20260912010000_phase8_ai_clinical_provenance.sql` → `20260912010001_phase8_ai_clinical_provenance.sql`
- `20260912021000_global_hims_operations.sql` → `20260912021001_global_hims_operations.sql`
- `20260912250000_reconciliation_finalization.sql` → `20260912250001_reconciliation_finalization.sql`
- `20260913180000_reports_center_submission_rbac.sql` → `20260913180001_reports_center_submission_rbac.sql`
- `20260914140000_theatre_emergency_transfusion_lifecycle_hardening.sql` → `20260914140001_theatre_emergency_transfusion_lifecycle_hardening.sql`
- `20260914150000_clinical_claim_nursing_direct_mutation_hardening.sql` → `20260914150001_clinical_claim_nursing_direct_mutation_hardening.sql`
- `20260915170000_remove_duplicate_insurance_claim_indexes.sql` → `20260915170001_remove_duplicate_insurance_claim_indexes.sql`
- `20260925200000_notification_inbound_email_store.sql` → `20260925200001_notification_inbound_email_store.sql`
- `20260929100000_insurance_company_master_data.sql` → `20260929100001_insurance_company_master_data.sql`
- `20260929103000_service_catalogue_department_control.sql` → `20260929103001_service_catalogue_department_control.sql`
- `20260929150000_operational_workspace_scope_hardening.sql` → `20260929150001_operational_workspace_scope_hardening.sql`
- `20260929150000_patient_canonical_insurer_linkage.sql` → `20260929150002_patient_canonical_insurer_linkage.sql`
- `20260929200000_role_dashboard_kpi_cleanup.sql` → `20260929200001_role_dashboard_kpi_cleanup.sql`
- `20260929203000_harden_security_definer_read_workspace_paths_batch6.sql` → `20260929203001_harden_security_definer_read_workspace_paths_batch6.sql`
- `20261002130000_scope_appointment_workflows_to_active_facility.sql` → `20261002130001_scope_appointment_workflows_to_active_facility.sql`
- `20261002132500_pharmacy_global_category_edit.sql` → `20261002132501_pharmacy_global_category_edit.sql`

### Three additional replacement-style collision candidates

The compare also shows three duplicate-version source files removed without Git classifying the replacement as a rename:

- `20260912162000_hims_workflow_completion.sql` is removed; the candidate branch modifies `20260912162001_hims_workflow_completion.sql` (52 additions, 21 deletions).
- `20260929200000_secure_default_function_execute_privileges.sql` is removed; `20260929200002_secure_default_function_execute_privileges.sql` is added (40 additions). The old and new SQL blobs differ.
- `20260930012000_harden_high_risk_rpc_execution_boundaries.sql` is removed; `20260930012001_harden_high_risk_rpc_execution_boundaries.sql` is added (50 additions). The old and new SQL blobs differ.

This yields 23 candidate collision treatments in total: 17 content-preserving renames and six SQL-changing treatments (three rename-classified changes plus three replacement-style changes). The candidate branch's compare is against `main`; it is not evidence that any replacement SQL is equivalent to the original applied payload or safe to execute in a particular environment.

### Decision

This classification improves the review inventory but does not clear the migration gate. Even a byte-identical rename changes the migration version identity and can cause a previously unapplied migration to become pending. The linked production ledger's absence of the candidate replacement versions does not establish the state of the legacy pre-Supabase environment or any other shared environment. No candidate was copied, renamed, deleted, or executed. The 21 duplicate groups remain unresolved, and the September baseline and three late-October laboratory source gaps remain independent replay blockers.

## 27. Latest migration-contract CI failure and source-recovery checks (2026-11-23)

The current PR head `045dfc97f77e0c4df1598ccc81e46a1734f4684a` was checked against GitHub Actions run `45213381767` (Migration contract, run #2809) and run `45213381877` (Quality, run #8890).

- Quality passed.
- Migration contract failed in both jobs before a database was started.
- Static job: forward-only regression, immutable-history enforcement, dependency installation, and migration-validation failure-semantics checks passed. The final `Validate migration identities and required contract assets` step failed.
- Database job: `Validate migration identities before starting database services` failed. Supabase CLI setup, local services, clean replay, and live schema/RPC/privilege/RLS verification were skipped.
- The validator calls `inspectMigrationDirectory` and rejects every duplicate 14-digit version and every invalid/unversioned directory entry. The known 21 duplicate version groups and `$(path)` entry therefore remain hard blockers. It also requires five non-empty database contract files and verifies workflow-referenced scripts exist; CI step output is not available from the artifact endpoint, so do not claim which individual required asset contributed beyond the migration inventory already independently established.
- Run #2809 has no retained GitHub Actions artifacts. The repository has no published GitHub releases. Path-scoped commit history queries for `20260916002251_canonical_remote_schema.sql` and `20260916003113_fix_start_imaging_order_queue_contract.sql` return no commits. This adds no recoverable provenance for either missing historical source.
- PR #444 Vercel bot reports its preview deployment as Ready, but that is not evidence of database migration replay or schema parity.

**Disposition:** keep PR #444 draft and unmerged. Do not rename/delete collision files, fabricate the missing baseline, bypass identity checks, or run production DDL. The next acceptable repair is to recover authenticated original SQL/schema evidence from the original pre-Supabase development environment or a verifiable backup, then classify each file against the live ledger and perform a clean disposable-database replay. If original baseline evidence cannot be recovered, prepare a separately approved bootstrap/upgrade strategy rather than rewriting deployed history.
