-- Performance reconciliation for foreign-key lookup paths.
-- This index inventory was generated from a provisioned schema. Some targets
-- are legacy-only tables or columns, so create each index only when its table
-- and column exist in the clean or partially provisioned installation.
DO $foreign_key_index_reconciliation$
DECLARE
  v_index record;
  v_relation regclass;
BEGIN
  FOR v_index IN
    SELECT * FROM (VALUES
      ('idx_fk_admissions_admitted_by', 'admissions', 'admitted_by'),
      ('idx_fk_ai_clinical_events_actor_id', 'ai_clinical_events', 'actor_id'),
      ('idx_fk_ai_clinical_sessions_created_by', 'ai_clinical_sessions', 'created_by'),
      ('idx_fk_ai_clinical_sessions_reviewed_by', 'ai_clinical_sessions', 'reviewed_by'),
      ('idx_fk_ai_diagnosis_suggestions_encounter_id', 'ai_diagnosis_suggestions', 'encounter_id'),
      ('idx_fk_ai_diagnosis_suggestions_suggested_icd', 'ai_diagnosis_suggestions', 'suggested_icd'),
      ('idx_fk_ai_protocols_approved_by', 'ai_protocols', 'approved_by'),
      ('idx_fk_ai_report_requests_patient_id', 'ai_report_requests', 'patient_id'),
      ('idx_fk_ai_report_requests_requested_by', 'ai_report_requests', 'requested_by'),
      ('idx_fk_ai_symptom_icd_map_icd_code', 'ai_symptom_icd_map', 'icd_code'),
      ('idx_fk_anesthetic_assessments_cleared_by', 'anesthetic_assessments', 'cleared_by'),
      ('idx_fk_anesthetic_assessments_encounter_id', 'anesthetic_assessments', 'encounter_id'),
      ('idx_fk_anesthetic_assessments_patient_id', 'anesthetic_assessments', 'patient_id'),
      ('idx_fk_audit_logs_user_id', 'audit_logs', 'user_id'),
      ('idx_fk_billing_overrides_overridden_by', 'billing_overrides', 'overridden_by'),
      ('idx_fk_billing_overrides_patient_id', 'billing_overrides', 'patient_id'),
      ('idx_fk_bulk_import_jobs_created_by', 'bulk_import_jobs', 'created_by'),
      ('idx_fk_care_transitions_responsible_officer', 'care_transitions', 'responsible_officer'),
      ('idx_fk_dental_records_performed_by', 'dental_records', 'performed_by'),
      ('idx_fk_diagnoses_icd_code', 'diagnoses', 'icd_code'),
      ('idx_fk_emergency_cases_assigned_officer', 'emergency_cases', 'assigned_officer'),
      ('idx_fk_facility_configuration_updated_by', 'facility_configuration', 'updated_by'),
      ('idx_fk_facility_report_config_report_id', 'facility_report_config', 'report_id'),
      ('idx_fk_healthcare_facilities_created_by', 'healthcare_facilities', 'created_by'),
      ('idx_fk_imaging_orders_encounter_id', 'imaging_orders', 'encounter_id'),
      ('idx_fk_imaging_orders_performed_by', 'imaging_orders', 'performed_by'),
      ('idx_fk_imaging_orders_requested_by', 'imaging_orders', 'requested_by'),
      ('idx_fk_imaging_orders_service_order_id', 'imaging_orders', 'service_order_id'),
      ('idx_fk_inpatient_reviews_patient_id', 'inpatient_reviews', 'patient_id'),
      ('idx_fk_inpatient_reviews_reviewed_by', 'inpatient_reviews', 'reviewed_by'),
      ('idx_fk_insurance_cases_checked_by', 'insurance_cases', 'checked_by'),
      ('idx_fk_lab_test_catalog_created_by', 'lab_test_catalog', 'created_by'),
      ('idx_fk_maternity_episodes_created_by', 'maternity_episodes', 'created_by'),
      ('idx_fk_maternity_observations_recorded_by', 'maternity_observations', 'recorded_by'),
      ('idx_fk_meal_orders_meal_plan_id', 'meal_orders', 'meal_plan_id'),
      ('idx_fk_meal_orders_patient_id', 'meal_orders', 'patient_id'),
      ('idx_fk_meal_plans_created_by', 'meal_plans', 'created_by'),
      ('idx_fk_meal_plans_patient_id', 'meal_plans', 'patient_id'),
      ('idx_fk_medication_administrations_administered_by', 'medication_administrations', 'administered_by'),
      ('idx_fk_medication_administrations_witnessed_by', 'medication_administrations', 'witnessed_by'),
      ('idx_fk_nursing_care_plans_created_by', 'nursing_care_plans', 'created_by'),
      ('idx_fk_nursing_care_plans_reviewed_by', 'nursing_care_plans', 'reviewed_by'),
      ('idx_fk_nursing_shift_handovers_incoming_officer', 'nursing_shift_handovers', 'incoming_officer'),
      ('idx_fk_nursing_shift_handovers_outgoing_officer', 'nursing_shift_handovers', 'outgoing_officer'),
      ('idx_fk_ophthalmology_exams_performed_by', 'ophthalmology_exams', 'performed_by'),
      ('idx_fk_ophthalmology_exams_reviewed_by', 'ophthalmology_exams', 'reviewed_by'),
      ('idx_fk_outside_lab_documents_reviewed_by', 'outside_lab_documents', 'reviewed_by'),
      ('idx_fk_outside_lab_documents_uploaded_by', 'outside_lab_documents', 'uploaded_by'),
      ('idx_fk_patient_referrals_referred_by', 'patient_referrals', 'referred_by'),
      ('idx_fk_pharmacy_dispensing_plans_dispensed_by', 'pharmacy_dispensing_plans', 'dispensed_by'),
      ('idx_fk_pharmacy_dispensing_plans_inventory_id', 'pharmacy_dispensing_plans', 'inventory_id'),
      ('idx_fk_pharmacy_dispensing_plans_invoice_item_id', 'pharmacy_dispensing_plans', 'invoice_item_id'),
      ('idx_fk_pharmacy_dispensing_plans_prepared_by', 'pharmacy_dispensing_plans', 'prepared_by'),
      ('idx_fk_pharmacy_dispensing_plans_prescription_id', 'pharmacy_dispensing_plans', 'prescription_id'),
      ('idx_fk_pharmacy_dispensing_plans_service_order_id', 'pharmacy_dispensing_plans', 'service_order_id'),
      ('idx_fk_pharmacy_goods_receipts_approved_by', 'pharmacy_goods_receipts', 'approved_by'),
      ('idx_fk_pharmacy_goods_receipts_inventory_id', 'pharmacy_goods_receipts', 'inventory_id'),
      ('idx_fk_pharmacy_goods_receipts_received_by', 'pharmacy_goods_receipts', 'received_by'),
      ('idx_fk_pharmacy_pos_sales_created_by', 'pharmacy_pos_sales', 'created_by'),
      ('idx_fk_pharmacy_pos_sales_dispensed_by', 'pharmacy_pos_sales', 'dispensed_by'),
      ('idx_fk_pharmacy_pos_sales_inventory_id', 'pharmacy_pos_sales', 'inventory_id'),
      ('idx_fk_pharmacy_pos_sales_patient_id', 'pharmacy_pos_sales', 'patient_id'),
      ('idx_fk_pharmacy_pos_sales_service_order_id', 'pharmacy_pos_sales', 'service_order_id'),
      ('idx_fk_procedure_notes_performed_by', 'procedure_notes', 'performed_by'),
      ('idx_fk_procedure_notes_service_order_id', 'procedure_notes', 'service_order_id'),
      ('idx_fk_report_definitions_category_id', 'report_definitions', 'category_id'),
      ('idx_fk_report_generation_items_report_id', 'report_generation_items', 'report_id'),
      ('idx_fk_report_generation_runs_created_by', 'report_generation_runs', 'created_by'),
      ('idx_fk_report_submissions_submitted_by', 'report_submissions', 'submitted_by'),
      ('idx_fk_service_orders_approved_by', 'service_orders', 'approved_by'),
      ('idx_fk_service_orders_released_by', 'service_orders', 'released_by'),
      ('idx_fk_staff_shift_assignments_user_id', 'staff_shift_assignments', 'user_id'),
      ('idx_fk_theatre_cases_anaesthetist_id', 'theatre_cases', 'anaesthetist_id'),
      ('idx_fk_theatre_cases_created_by', 'theatre_cases', 'created_by'),
      ('idx_fk_theatre_cases_encounter_id', 'theatre_cases', 'encounter_id'),
      ('idx_fk_theatre_cases_patient_id', 'theatre_cases', 'patient_id'),
      ('idx_fk_theatre_cases_surgeon_id', 'theatre_cases', 'surgeon_id'),
      ('idx_fk_transfusion_records_administered_by', 'transfusion_records', 'administered_by'),
      ('idx_fk_transfusion_records_encounter_id', 'transfusion_records', 'encounter_id'),
      ('idx_fk_transfusion_records_witnessed_by', 'transfusion_records', 'witnessed_by'),
      ('idx_fk_treatment_templates_created_by', 'treatment_templates', 'created_by'),
      ('idx_fk_vital_alerts_acknowledged_by', 'vital_alerts', 'acknowledged_by'),
      ('idx_fk_vital_alerts_patient_id', 'vital_alerts', 'patient_id'),
      ('idx_fk_ward_beds_patient_id', 'ward_beds', 'patient_id'),
      ('idx_fk_diagnosis_import_batches_approved_by', 'diagnosis_import_batches', 'approved_by'),
      ('idx_fk_diagnosis_import_batches_created_by', 'diagnosis_import_batches', 'created_by'),
      ('idx_fk_diagnosis_import_rows_icd10_code_id', 'diagnosis_import_rows', 'icd10_code_id'),
      ('idx_fk_diagnosis_standard_mappings_reviewed_by', 'diagnosis_standard_mappings', 'reviewed_by'),
      ('idx_fk_stg_diagnoses_icd10_code_id', 'stg_diagnoses', 'icd10_code_id'),
      ('idx_fk_facility_diagnosis_standards_standard_id', 'facility_diagnosis_standards', 'standard_id')
    ) AS requested(index_name, table_name, column_name)
  LOOP
    v_relation := to_regclass(format('public.%I', v_index.table_name));
    IF v_relation IS NOT NULL
       AND EXISTS (
         SELECT 1
         FROM pg_attribute
         WHERE attrelid = v_relation
           AND attname = v_index.column_name
           AND attnum > 0
           AND NOT attisdropped
       ) THEN
      EXECUTE format(
        'CREATE INDEX IF NOT EXISTS %I ON public.%I (%I)',
        v_index.index_name,
        v_index.table_name,
        v_index.column_name
      );
    END IF;
  END LOOP;
END;
$foreign_key_index_reconciliation$;
