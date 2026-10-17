-- Performance reconciliation: every public foreign key now has a covering index.
-- Generated from the live production schema and applied as migration 20260916103212.
-- Keep IF NOT EXISTS so re-running against a reconciled schema is harmless.

DO $migration$ BEGIN
  -- Production reconciliation may include legacy relations absent from a clean install.
  IF to_regclass('public.admissions') IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'admissions' AND column_name = 'admitted_by') THEN
    EXECUTE 'create index if not exists idx_fk_admissions_admitted_by on public.admissions (admitted_by);';
  END IF;
END $migration$;
DO $migration$ BEGIN
  -- Production reconciliation may include legacy relations absent from a clean install.
  IF to_regclass('public.ai_clinical_events') IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'ai_clinical_events' AND column_name = 'actor_id') THEN
    EXECUTE 'create index if not exists idx_fk_ai_clinical_events_actor_id on public.ai_clinical_events (actor_id);';
  END IF;
END $migration$;
DO $migration$ BEGIN
  -- Production reconciliation may include legacy relations absent from a clean install.
  IF to_regclass('public.ai_clinical_sessions') IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'ai_clinical_sessions' AND column_name = 'created_by') THEN
    EXECUTE 'create index if not exists idx_fk_ai_clinical_sessions_created_by on public.ai_clinical_sessions (created_by);';
  END IF;
END $migration$;
DO $migration$ BEGIN
  -- Production reconciliation may include legacy relations absent from a clean install.
  IF to_regclass('public.ai_clinical_sessions') IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'ai_clinical_sessions' AND column_name = 'reviewed_by') THEN
    EXECUTE 'create index if not exists idx_fk_ai_clinical_sessions_reviewed_by on public.ai_clinical_sessions (reviewed_by);';
  END IF;
END $migration$;
DO $migration$ BEGIN
  -- Production reconciliation may include legacy relations absent from a clean install.
  IF to_regclass('public.ai_diagnosis_suggestions') IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'ai_diagnosis_suggestions' AND column_name = 'encounter_id') THEN
    EXECUTE 'create index if not exists idx_fk_ai_diagnosis_suggestions_encounter_id on public.ai_diagnosis_suggestions (encounter_id);';
  END IF;
END $migration$;
DO $migration$ BEGIN
  -- Production reconciliation may include legacy relations absent from a clean install.
  IF to_regclass('public.ai_diagnosis_suggestions') IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'ai_diagnosis_suggestions' AND column_name = 'suggested_icd') THEN
    EXECUTE 'create index if not exists idx_fk_ai_diagnosis_suggestions_suggested_icd on public.ai_diagnosis_suggestions (suggested_icd);';
  END IF;
END $migration$;
DO $migration$ BEGIN
  -- Production reconciliation may include legacy relations absent from a clean install.
  IF to_regclass('public.ai_protocols') IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'ai_protocols' AND column_name = 'approved_by') THEN
    EXECUTE 'create index if not exists idx_fk_ai_protocols_approved_by on public.ai_protocols (approved_by);';
  END IF;
END $migration$;
DO $migration$ BEGIN
  -- Production reconciliation may include legacy relations absent from a clean install.
  IF to_regclass('public.ai_report_requests') IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'ai_report_requests' AND column_name = 'patient_id') THEN
    EXECUTE 'create index if not exists idx_fk_ai_report_requests_patient_id on public.ai_report_requests (patient_id);';
  END IF;
END $migration$;
DO $migration$ BEGIN
  -- Production reconciliation may include legacy relations absent from a clean install.
  IF to_regclass('public.ai_report_requests') IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'ai_report_requests' AND column_name = 'requested_by') THEN
    EXECUTE 'create index if not exists idx_fk_ai_report_requests_requested_by on public.ai_report_requests (requested_by);';
  END IF;
END $migration$;
DO $migration$ BEGIN
  -- Production reconciliation may include legacy relations absent from a clean install.
  IF to_regclass('public.ai_symptom_icd_map') IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'ai_symptom_icd_map' AND column_name = 'icd_code') THEN
    EXECUTE 'create index if not exists idx_fk_ai_symptom_icd_map_icd_code on public.ai_symptom_icd_map (icd_code);';
  END IF;
END $migration$;
DO $migration$ BEGIN
  -- Production reconciliation may include legacy relations absent from a clean install.
  IF to_regclass('public.anesthetic_assessments') IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'anesthetic_assessments' AND column_name = 'cleared_by') THEN
    EXECUTE 'create index if not exists idx_fk_anesthetic_assessments_cleared_by on public.anesthetic_assessments (cleared_by);';
  END IF;
END $migration$;
DO $migration$ BEGIN
  -- Production reconciliation may include legacy relations absent from a clean install.
  IF to_regclass('public.anesthetic_assessments') IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'anesthetic_assessments' AND column_name = 'encounter_id') THEN
    EXECUTE 'create index if not exists idx_fk_anesthetic_assessments_encounter_id on public.anesthetic_assessments (encounter_id);';
  END IF;
END $migration$;
DO $migration$ BEGIN
  -- Production reconciliation may include legacy relations absent from a clean install.
  IF to_regclass('public.anesthetic_assessments') IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'anesthetic_assessments' AND column_name = 'patient_id') THEN
    EXECUTE 'create index if not exists idx_fk_anesthetic_assessments_patient_id on public.anesthetic_assessments (patient_id);';
  END IF;
END $migration$;
DO $migration$ BEGIN
  -- Production reconciliation may include legacy relations absent from a clean install.
  IF to_regclass('public.audit_logs') IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'audit_logs' AND column_name = 'user_id') THEN
    EXECUTE 'create index if not exists idx_fk_audit_logs_user_id on public.audit_logs (user_id);';
  END IF;
END $migration$;
DO $migration$ BEGIN
  -- Production reconciliation may include legacy relations absent from a clean install.
  IF to_regclass('public.billing_overrides') IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'billing_overrides' AND column_name = 'overridden_by') THEN
    EXECUTE 'create index if not exists idx_fk_billing_overrides_overridden_by on public.billing_overrides (overridden_by);';
  END IF;
END $migration$;
DO $migration$ BEGIN
  -- Production reconciliation may include legacy relations absent from a clean install.
  IF to_regclass('public.billing_overrides') IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'billing_overrides' AND column_name = 'patient_id') THEN
    EXECUTE 'create index if not exists idx_fk_billing_overrides_patient_id on public.billing_overrides (patient_id);';
  END IF;
END $migration$;
DO $migration$ BEGIN
  -- Production reconciliation may include legacy relations absent from a clean install.
  IF to_regclass('public.bulk_import_jobs') IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'bulk_import_jobs' AND column_name = 'created_by') THEN
    EXECUTE 'create index if not exists idx_fk_bulk_import_jobs_created_by on public.bulk_import_jobs (created_by);';
  END IF;
END $migration$;
DO $migration$ BEGIN
  -- Production reconciliation may include legacy relations absent from a clean install.
  IF to_regclass('public.care_transitions') IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'care_transitions' AND column_name = 'responsible_officer') THEN
    EXECUTE 'create index if not exists idx_fk_care_transitions_responsible_officer on public.care_transitions (responsible_officer);';
  END IF;
END $migration$;
DO $migration$ BEGIN
  -- Production reconciliation may include legacy relations absent from a clean install.
  IF to_regclass('public.dental_records') IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'dental_records' AND column_name = 'performed_by') THEN
    EXECUTE 'create index if not exists idx_fk_dental_records_performed_by on public.dental_records (performed_by);';
  END IF;
END $migration$;
DO $migration$ BEGIN
  -- Production reconciliation may include legacy relations absent from a clean install.
  IF to_regclass('public.diagnoses') IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'diagnoses' AND column_name = 'icd_code') THEN
    EXECUTE 'create index if not exists idx_fk_diagnoses_icd_code on public.diagnoses (icd_code);';
  END IF;
END $migration$;
DO $migration$ BEGIN
  -- Production reconciliation may include legacy relations absent from a clean install.
  IF to_regclass('public.diagnosis_import_batches') IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'diagnosis_import_batches' AND column_name = 'approved_by') THEN
    EXECUTE 'create index if not exists idx_fk_diagnosis_import_batches_approved_by on public.diagnosis_import_batches (approved_by);';
  END IF;
END $migration$;
DO $migration$ BEGIN
  -- Production reconciliation may include legacy relations absent from a clean install.
  IF to_regclass('public.diagnosis_import_batches') IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'diagnosis_import_batches' AND column_name = 'created_by') THEN
    EXECUTE 'create index if not exists idx_fk_diagnosis_import_batches_created_by on public.diagnosis_import_batches (created_by);';
  END IF;
END $migration$;
DO $migration$ BEGIN
  -- Production reconciliation may include legacy relations absent from a clean install.
  IF to_regclass('public.diagnosis_import_rows') IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'diagnosis_import_rows' AND column_name = 'icd10_code_id') THEN
    EXECUTE 'create index if not exists idx_fk_diagnosis_import_rows_icd10_code_id on public.diagnosis_import_rows (icd10_code_id);';
  END IF;
END $migration$;
DO $migration$ BEGIN
  -- Production reconciliation may include legacy relations absent from a clean install.
  IF to_regclass('public.diagnosis_standard_mappings') IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'diagnosis_standard_mappings' AND column_name = 'reviewed_by') THEN
    EXECUTE 'create index if not exists idx_fk_diagnosis_standard_mappings_reviewed_by on public.diagnosis_standard_mappings (reviewed_by);';
  END IF;
END $migration$;
DO $migration$ BEGIN
  -- Production reconciliation may include legacy relations absent from a clean install.
  IF to_regclass('public.emergency_cases') IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'emergency_cases' AND column_name = 'assigned_officer') THEN
    EXECUTE 'create index if not exists idx_fk_emergency_cases_assigned_officer on public.emergency_cases (assigned_officer);';
  END IF;
END $migration$;
DO $migration$ BEGIN
  -- Production reconciliation may include legacy relations absent from a clean install.
  IF to_regclass('public.facility_configuration') IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'facility_configuration' AND column_name = 'updated_by') THEN
    EXECUTE 'create index if not exists idx_fk_facility_configuration_updated_by on public.facility_configuration (updated_by);';
  END IF;
END $migration$;
DO $migration$ BEGIN
  -- Production reconciliation may include legacy relations absent from a clean install.
  IF to_regclass('public.facility_diagnosis_standards') IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'facility_diagnosis_standards' AND column_name = 'standard_id') THEN
    EXECUTE 'create index if not exists idx_fk_facility_diagnosis_standards_standard_id on public.facility_diagnosis_standards (standard_id);';
  END IF;
END $migration$;
DO $migration$ BEGIN
  -- Production reconciliation may include legacy relations absent from a clean install.
  IF to_regclass('public.facility_report_config') IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'facility_report_config' AND column_name = 'report_id') THEN
    EXECUTE 'create index if not exists idx_fk_facility_report_config_report_id on public.facility_report_config (report_id);';
  END IF;
END $migration$;
DO $migration$ BEGIN
  -- Production reconciliation may include legacy relations absent from a clean install.
  IF to_regclass('public.healthcare_facilities') IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'healthcare_facilities' AND column_name = 'created_by') THEN
    EXECUTE 'create index if not exists idx_fk_healthcare_facilities_created_by on public.healthcare_facilities (created_by);';
  END IF;
END $migration$;
DO $migration$ BEGIN
  -- Production reconciliation may include legacy relations absent from a clean install.
  IF to_regclass('public.imaging_orders') IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'imaging_orders' AND column_name = 'encounter_id') THEN
    EXECUTE 'create index if not exists idx_fk_imaging_orders_encounter_id on public.imaging_orders (encounter_id);';
  END IF;
END $migration$;
DO $migration$ BEGIN
  -- Production reconciliation may include legacy relations absent from a clean install.
  IF to_regclass('public.imaging_orders') IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'imaging_orders' AND column_name = 'performed_by') THEN
    EXECUTE 'create index if not exists idx_fk_imaging_orders_performed_by on public.imaging_orders (performed_by);';
  END IF;
END $migration$;
DO $migration$ BEGIN
  -- Production reconciliation may include legacy relations absent from a clean install.
  IF to_regclass('public.imaging_orders') IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'imaging_orders' AND column_name = 'requested_by') THEN
    EXECUTE 'create index if not exists idx_fk_imaging_orders_requested_by on public.imaging_orders (requested_by);';
  END IF;
END $migration$;
DO $migration$ BEGIN
  -- Production reconciliation may include legacy relations absent from a clean install.
  IF to_regclass('public.imaging_orders') IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'imaging_orders' AND column_name = 'service_order_id') THEN
    EXECUTE 'create index if not exists idx_fk_imaging_orders_service_order_id on public.imaging_orders (service_order_id);';
  END IF;
END $migration$;
DO $migration$ BEGIN
  -- Production reconciliation may include legacy relations absent from a clean install.
  IF to_regclass('public.inpatient_reviews') IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'inpatient_reviews' AND column_name = 'patient_id') THEN
    EXECUTE 'create index if not exists idx_fk_inpatient_reviews_patient_id on public.inpatient_reviews (patient_id);';
  END IF;
END $migration$;
DO $migration$ BEGIN
  -- Production reconciliation may include legacy relations absent from a clean install.
  IF to_regclass('public.inpatient_reviews') IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'inpatient_reviews' AND column_name = 'reviewed_by') THEN
    EXECUTE 'create index if not exists idx_fk_inpatient_reviews_reviewed_by on public.inpatient_reviews (reviewed_by);';
  END IF;
END $migration$;
DO $migration$ BEGIN
  -- Production reconciliation may include legacy relations absent from a clean install.
  IF to_regclass('public.insurance_cases') IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'insurance_cases' AND column_name = 'checked_by') THEN
    EXECUTE 'create index if not exists idx_fk_insurance_cases_checked_by on public.insurance_cases (checked_by);';
  END IF;
END $migration$;
DO $migration$ BEGIN
  -- Production reconciliation may include legacy relations absent from a clean install.
  IF to_regclass('public.lab_test_catalog') IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'lab_test_catalog' AND column_name = 'created_by') THEN
    EXECUTE 'create index if not exists idx_fk_lab_test_catalog_created_by on public.lab_test_catalog (created_by);';
  END IF;
END $migration$;
DO $migration$ BEGIN
  -- Production reconciliation may include legacy relations absent from a clean install.
  IF to_regclass('public.maternity_episodes') IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'maternity_episodes' AND column_name = 'created_by') THEN
    EXECUTE 'create index if not exists idx_fk_maternity_episodes_created_by on public.maternity_episodes (created_by);';
  END IF;
END $migration$;
DO $migration$ BEGIN
  -- Production reconciliation may include legacy relations absent from a clean install.
  IF to_regclass('public.maternity_observations') IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'maternity_observations' AND column_name = 'recorded_by') THEN
    EXECUTE 'create index if not exists idx_fk_maternity_observations_recorded_by on public.maternity_observations (recorded_by);';
  END IF;
END $migration$;
DO $migration$ BEGIN
  -- Production reconciliation may include legacy relations absent from a clean install.
  IF to_regclass('public.meal_orders') IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'meal_orders' AND column_name = 'meal_plan_id') THEN
    EXECUTE 'create index if not exists idx_fk_meal_orders_meal_plan_id on public.meal_orders (meal_plan_id);';
  END IF;
END $migration$;
DO $migration$ BEGIN
  -- Production reconciliation may include legacy relations absent from a clean install.
  IF to_regclass('public.meal_orders') IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'meal_orders' AND column_name = 'patient_id') THEN
    EXECUTE 'create index if not exists idx_fk_meal_orders_patient_id on public.meal_orders (patient_id);';
  END IF;
END $migration$;
DO $migration$ BEGIN
  -- Production reconciliation may include legacy relations absent from a clean install.
  IF to_regclass('public.meal_plans') IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'meal_plans' AND column_name = 'created_by') THEN
    EXECUTE 'create index if not exists idx_fk_meal_plans_created_by on public.meal_plans (created_by);';
  END IF;
END $migration$;
DO $migration$ BEGIN
  -- Production reconciliation may include legacy relations absent from a clean install.
  IF to_regclass('public.meal_plans') IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'meal_plans' AND column_name = 'patient_id') THEN
    EXECUTE 'create index if not exists idx_fk_meal_plans_patient_id on public.meal_plans (patient_id);';
  END IF;
END $migration$;
DO $migration$ BEGIN
  -- Production reconciliation may include legacy relations absent from a clean install.
  IF to_regclass('public.medication_administrations') IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'medication_administrations' AND column_name = 'administered_by') THEN
    EXECUTE 'create index if not exists idx_fk_medication_administrations_administered_by on public.medication_administrations (administered_by);';
  END IF;
END $migration$;
DO $migration$ BEGIN
  -- Production reconciliation may include legacy relations absent from a clean install.
  IF to_regclass('public.medication_administrations') IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'medication_administrations' AND column_name = 'witnessed_by') THEN
    EXECUTE 'create index if not exists idx_fk_medication_administrations_witnessed_by on public.medication_administrations (witnessed_by);';
  END IF;
END $migration$;
DO $migration$ BEGIN
  -- Production reconciliation may include legacy relations absent from a clean install.
  IF to_regclass('public.nursing_care_plans') IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'nursing_care_plans' AND column_name = 'created_by') THEN
    EXECUTE 'create index if not exists idx_fk_nursing_care_plans_created_by on public.nursing_care_plans (created_by);';
  END IF;
END $migration$;
DO $migration$ BEGIN
  -- Production reconciliation may include legacy relations absent from a clean install.
  IF to_regclass('public.nursing_care_plans') IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'nursing_care_plans' AND column_name = 'reviewed_by') THEN
    EXECUTE 'create index if not exists idx_fk_nursing_care_plans_reviewed_by on public.nursing_care_plans (reviewed_by);';
  END IF;
END $migration$;
DO $migration$ BEGIN
  -- Production reconciliation may include legacy relations absent from a clean install.
  IF to_regclass('public.nursing_shift_handovers') IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'nursing_shift_handovers' AND column_name = 'incoming_officer') THEN
    EXECUTE 'create index if not exists idx_fk_nursing_shift_handovers_incoming_officer on public.nursing_shift_handovers (incoming_officer);';
  END IF;
END $migration$;
DO $migration$ BEGIN
  -- Production reconciliation may include legacy relations absent from a clean install.
  IF to_regclass('public.nursing_shift_handovers') IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'nursing_shift_handovers' AND column_name = 'outgoing_officer') THEN
    EXECUTE 'create index if not exists idx_fk_nursing_shift_handovers_outgoing_officer on public.nursing_shift_handovers (outgoing_officer);';
  END IF;
END $migration$;
DO $migration$ BEGIN
  -- Production reconciliation may include legacy relations absent from a clean install.
  IF to_regclass('public.ophthalmology_exams') IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'ophthalmology_exams' AND column_name = 'performed_by') THEN
    EXECUTE 'create index if not exists idx_fk_ophthalmology_exams_performed_by on public.ophthalmology_exams (performed_by);';
  END IF;
END $migration$;
DO $migration$ BEGIN
  -- Production reconciliation may include legacy relations absent from a clean install.
  IF to_regclass('public.ophthalmology_exams') IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'ophthalmology_exams' AND column_name = 'reviewed_by') THEN
    EXECUTE 'create index if not exists idx_fk_ophthalmology_exams_reviewed_by on public.ophthalmology_exams (reviewed_by);';
  END IF;
END $migration$;
DO $migration$ BEGIN
  -- Production reconciliation may include legacy relations absent from a clean install.
  IF to_regclass('public.outside_lab_documents') IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'outside_lab_documents' AND column_name = 'reviewed_by') THEN
    EXECUTE 'create index if not exists idx_fk_outside_lab_documents_reviewed_by on public.outside_lab_documents (reviewed_by);';
  END IF;
END $migration$;
DO $migration$ BEGIN
  -- Production reconciliation may include legacy relations absent from a clean install.
  IF to_regclass('public.outside_lab_documents') IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'outside_lab_documents' AND column_name = 'uploaded_by') THEN
    EXECUTE 'create index if not exists idx_fk_outside_lab_documents_uploaded_by on public.outside_lab_documents (uploaded_by);';
  END IF;
END $migration$;
DO $migration$ BEGIN
  -- Production reconciliation may include legacy relations absent from a clean install.
  IF to_regclass('public.patient_referrals') IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'patient_referrals' AND column_name = 'referred_by') THEN
    EXECUTE 'create index if not exists idx_fk_patient_referrals_referred_by on public.patient_referrals (referred_by);';
  END IF;
END $migration$;
DO $migration$ BEGIN
  -- Production reconciliation may include legacy relations absent from a clean install.
  IF to_regclass('public.pharmacy_dispensing_plans') IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'pharmacy_dispensing_plans' AND column_name = 'dispensed_by') THEN
    EXECUTE 'create index if not exists idx_fk_pharmacy_dispensing_plans_dispensed_by on public.pharmacy_dispensing_plans (dispensed_by);';
  END IF;
END $migration$;
DO $migration$ BEGIN
  -- Production reconciliation may include legacy relations absent from a clean install.
  IF to_regclass('public.pharmacy_dispensing_plans') IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'pharmacy_dispensing_plans' AND column_name = 'inventory_id') THEN
    EXECUTE 'create index if not exists idx_fk_pharmacy_dispensing_plans_inventory_id on public.pharmacy_dispensing_plans (inventory_id);';
  END IF;
END $migration$;
DO $migration$ BEGIN
  -- Production reconciliation may include legacy relations absent from a clean install.
  IF to_regclass('public.pharmacy_dispensing_plans') IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'pharmacy_dispensing_plans' AND column_name = 'invoice_item_id') THEN
    EXECUTE 'create index if not exists idx_fk_pharmacy_dispensing_plans_invoice_item_id on public.pharmacy_dispensing_plans (invoice_item_id);';
  END IF;
END $migration$;
DO $migration$ BEGIN
  -- Production reconciliation may include legacy relations absent from a clean install.
  IF to_regclass('public.pharmacy_dispensing_plans') IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'pharmacy_dispensing_plans' AND column_name = 'prepared_by') THEN
    EXECUTE 'create index if not exists idx_fk_pharmacy_dispensing_plans_prepared_by on public.pharmacy_dispensing_plans (prepared_by);';
  END IF;
END $migration$;
DO $migration$ BEGIN
  -- Production reconciliation may include legacy relations absent from a clean install.
  IF to_regclass('public.pharmacy_dispensing_plans') IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'pharmacy_dispensing_plans' AND column_name = 'prescription_id') THEN
    EXECUTE 'create index if not exists idx_fk_pharmacy_dispensing_plans_prescription_id on public.pharmacy_dispensing_plans (prescription_id);';
  END IF;
END $migration$;
DO $migration$ BEGIN
  -- Production reconciliation may include legacy relations absent from a clean install.
  IF to_regclass('public.pharmacy_dispensing_plans') IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'pharmacy_dispensing_plans' AND column_name = 'service_order_id') THEN
    EXECUTE 'create index if not exists idx_fk_pharmacy_dispensing_plans_service_order_id on public.pharmacy_dispensing_plans (service_order_id);';
  END IF;
END $migration$;
DO $migration$ BEGIN
  -- Production reconciliation may include legacy relations absent from a clean install.
  IF to_regclass('public.pharmacy_goods_receipts') IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'pharmacy_goods_receipts' AND column_name = 'approved_by') THEN
    EXECUTE 'create index if not exists idx_fk_pharmacy_goods_receipts_approved_by on public.pharmacy_goods_receipts (approved_by);';
  END IF;
END $migration$;
DO $migration$ BEGIN
  -- Production reconciliation may include legacy relations absent from a clean install.
  IF to_regclass('public.pharmacy_goods_receipts') IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'pharmacy_goods_receipts' AND column_name = 'inventory_id') THEN
    EXECUTE 'create index if not exists idx_fk_pharmacy_goods_receipts_inventory_id on public.pharmacy_goods_receipts (inventory_id);';
  END IF;
END $migration$;
DO $migration$ BEGIN
  -- Production reconciliation may include legacy relations absent from a clean install.
  IF to_regclass('public.pharmacy_goods_receipts') IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'pharmacy_goods_receipts' AND column_name = 'received_by') THEN
    EXECUTE 'create index if not exists idx_fk_pharmacy_goods_receipts_received_by on public.pharmacy_goods_receipts (received_by);';
  END IF;
END $migration$;
DO $migration$ BEGIN
  -- Production reconciliation may include legacy relations absent from a clean install.
  IF to_regclass('public.pharmacy_pos_sales') IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'pharmacy_pos_sales' AND column_name = 'created_by') THEN
    EXECUTE 'create index if not exists idx_fk_pharmacy_pos_sales_created_by on public.pharmacy_pos_sales (created_by);';
  END IF;
END $migration$;
DO $migration$ BEGIN
  -- Production reconciliation may include legacy relations absent from a clean install.
  IF to_regclass('public.pharmacy_pos_sales') IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'pharmacy_pos_sales' AND column_name = 'dispensed_by') THEN
    EXECUTE 'create index if not exists idx_fk_pharmacy_pos_sales_dispensed_by on public.pharmacy_pos_sales (dispensed_by);';
  END IF;
END $migration$;
DO $migration$ BEGIN
  -- Production reconciliation may include legacy relations absent from a clean install.
  IF to_regclass('public.pharmacy_pos_sales') IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'pharmacy_pos_sales' AND column_name = 'inventory_id') THEN
    EXECUTE 'create index if not exists idx_fk_pharmacy_pos_sales_inventory_id on public.pharmacy_pos_sales (inventory_id);';
  END IF;
END $migration$;
DO $migration$ BEGIN
  -- Production reconciliation may include legacy relations absent from a clean install.
  IF to_regclass('public.pharmacy_pos_sales') IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'pharmacy_pos_sales' AND column_name = 'patient_id') THEN
    EXECUTE 'create index if not exists idx_fk_pharmacy_pos_sales_patient_id on public.pharmacy_pos_sales (patient_id);';
  END IF;
END $migration$;
DO $migration$ BEGIN
  -- Production reconciliation may include legacy relations absent from a clean install.
  IF to_regclass('public.pharmacy_pos_sales') IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'pharmacy_pos_sales' AND column_name = 'service_order_id') THEN
    EXECUTE 'create index if not exists idx_fk_pharmacy_pos_sales_service_order_id on public.pharmacy_pos_sales (service_order_id);';
  END IF;
END $migration$;
DO $migration$ BEGIN
  -- Production reconciliation may include legacy relations absent from a clean install.
  IF to_regclass('public.procedure_notes') IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'procedure_notes' AND column_name = 'performed_by') THEN
    EXECUTE 'create index if not exists idx_fk_procedure_notes_performed_by on public.procedure_notes (performed_by);';
  END IF;
END $migration$;
DO $migration$ BEGIN
  -- Production reconciliation may include legacy relations absent from a clean install.
  IF to_regclass('public.procedure_notes') IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'procedure_notes' AND column_name = 'service_order_id') THEN
    EXECUTE 'create index if not exists idx_fk_procedure_notes_service_order_id on public.procedure_notes (service_order_id);';
  END IF;
END $migration$;
DO $migration$ BEGIN
  -- Production reconciliation may include legacy relations absent from a clean install.
  IF to_regclass('public.report_definitions') IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'report_definitions' AND column_name = 'category_id') THEN
    EXECUTE 'create index if not exists idx_fk_report_definitions_category_id on public.report_definitions (category_id);';
  END IF;
END $migration$;
DO $migration$ BEGIN
  -- Production reconciliation may include legacy relations absent from a clean install.
  IF to_regclass('public.report_generation_items') IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'report_generation_items' AND column_name = 'report_id') THEN
    EXECUTE 'create index if not exists idx_fk_report_generation_items_report_id on public.report_generation_items (report_id);';
  END IF;
END $migration$;
DO $migration$ BEGIN
  -- Production reconciliation may include legacy relations absent from a clean install.
  IF to_regclass('public.report_generation_runs') IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'report_generation_runs' AND column_name = 'created_by') THEN
    EXECUTE 'create index if not exists idx_fk_report_generation_runs_created_by on public.report_generation_runs (created_by);';
  END IF;
END $migration$;
DO $migration$ BEGIN
  -- Production reconciliation may include legacy relations absent from a clean install.
  IF to_regclass('public.report_submissions') IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'report_submissions' AND column_name = 'submitted_by') THEN
    EXECUTE 'create index if not exists idx_fk_report_submissions_submitted_by on public.report_submissions (submitted_by);';
  END IF;
END $migration$;
DO $migration$ BEGIN
  -- Production reconciliation may include legacy relations absent from a clean install.
  IF to_regclass('public.service_orders') IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'service_orders' AND column_name = 'approved_by') THEN
    EXECUTE 'create index if not exists idx_fk_service_orders_approved_by on public.service_orders (approved_by);';
  END IF;
END $migration$;
DO $migration$ BEGIN
  -- Production reconciliation may include legacy relations absent from a clean install.
  IF to_regclass('public.service_orders') IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'service_orders' AND column_name = 'released_by') THEN
    EXECUTE 'create index if not exists idx_fk_service_orders_released_by on public.service_orders (released_by);';
  END IF;
END $migration$;
DO $migration$ BEGIN
  -- Production reconciliation may include legacy relations absent from a clean install.
  IF to_regclass('public.staff_shift_assignments') IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'staff_shift_assignments' AND column_name = 'user_id') THEN
    EXECUTE 'create index if not exists idx_fk_staff_shift_assignments_user_id on public.staff_shift_assignments (user_id);';
  END IF;
END $migration$;
DO $migration$ BEGIN
  -- Production reconciliation may include legacy relations absent from a clean install.
  IF to_regclass('public.stg_diagnoses') IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'stg_diagnoses' AND column_name = 'icd10_code_id') THEN
    EXECUTE 'create index if not exists idx_fk_stg_diagnoses_icd10_code_id on public.stg_diagnoses (icd10_code_id);';
  END IF;
END $migration$;
DO $migration$ BEGIN
  -- Production reconciliation may include legacy relations absent from a clean install.
  IF to_regclass('public.theatre_cases') IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'theatre_cases' AND column_name = 'anaesthetist_id') THEN
    EXECUTE 'create index if not exists idx_fk_theatre_cases_anaesthetist_id on public.theatre_cases (anaesthetist_id);';
  END IF;
END $migration$;
DO $migration$ BEGIN
  -- Production reconciliation may include legacy relations absent from a clean install.
  IF to_regclass('public.theatre_cases') IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'theatre_cases' AND column_name = 'created_by') THEN
    EXECUTE 'create index if not exists idx_fk_theatre_cases_created_by on public.theatre_cases (created_by);';
  END IF;
END $migration$;
DO $migration$ BEGIN
  -- Production reconciliation may include legacy relations absent from a clean install.
  IF to_regclass('public.theatre_cases') IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'theatre_cases' AND column_name = 'encounter_id') THEN
    EXECUTE 'create index if not exists idx_fk_theatre_cases_encounter_id on public.theatre_cases (encounter_id);';
  END IF;
END $migration$;
DO $migration$ BEGIN
  -- Production reconciliation may include legacy relations absent from a clean install.
  IF to_regclass('public.theatre_cases') IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'theatre_cases' AND column_name = 'patient_id') THEN
    EXECUTE 'create index if not exists idx_fk_theatre_cases_patient_id on public.theatre_cases (patient_id);';
  END IF;
END $migration$;
DO $migration$ BEGIN
  -- Production reconciliation may include legacy relations absent from a clean install.
  IF to_regclass('public.theatre_cases') IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'theatre_cases' AND column_name = 'surgeon_id') THEN
    EXECUTE 'create index if not exists idx_fk_theatre_cases_surgeon_id on public.theatre_cases (surgeon_id);';
  END IF;
END $migration$;
DO $migration$ BEGIN
  -- Production reconciliation may include legacy relations absent from a clean install.
  IF to_regclass('public.transfusion_records') IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'transfusion_records' AND column_name = 'administered_by') THEN
    EXECUTE 'create index if not exists idx_fk_transfusion_records_administered_by on public.transfusion_records (administered_by);';
  END IF;
END $migration$;
DO $migration$ BEGIN
  -- Production reconciliation may include legacy relations absent from a clean install.
  IF to_regclass('public.transfusion_records') IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'transfusion_records' AND column_name = 'encounter_id') THEN
    EXECUTE 'create index if not exists idx_fk_transfusion_records_encounter_id on public.transfusion_records (encounter_id);';
  END IF;
END $migration$;
DO $migration$ BEGIN
  -- Production reconciliation may include legacy relations absent from a clean install.
  IF to_regclass('public.transfusion_records') IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'transfusion_records' AND column_name = 'witnessed_by') THEN
    EXECUTE 'create index if not exists idx_fk_transfusion_records_witnessed_by on public.transfusion_records (witnessed_by);';
  END IF;
END $migration$;
DO $migration$ BEGIN
  -- Production reconciliation may include legacy relations absent from a clean install.
  IF to_regclass('public.treatment_templates') IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'treatment_templates' AND column_name = 'created_by') THEN
    EXECUTE 'create index if not exists idx_fk_treatment_templates_created_by on public.treatment_templates (created_by);';
  END IF;
END $migration$;
DO $migration$ BEGIN
  -- Production reconciliation may include legacy relations absent from a clean install.
  IF to_regclass('public.vital_alerts') IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'vital_alerts' AND column_name = 'acknowledged_by') THEN
    EXECUTE 'create index if not exists idx_fk_vital_alerts_acknowledged_by on public.vital_alerts (acknowledged_by);';
  END IF;
END $migration$;
DO $migration$ BEGIN
  -- Production reconciliation may include legacy relations absent from a clean install.
  IF to_regclass('public.vital_alerts') IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'vital_alerts' AND column_name = 'patient_id') THEN
    EXECUTE 'create index if not exists idx_fk_vital_alerts_patient_id on public.vital_alerts (patient_id);';
  END IF;
END $migration$;
DO $migration$ BEGIN
  -- Production reconciliation may include legacy relations absent from a clean install.
  IF to_regclass('public.ward_beds') IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'ward_beds' AND column_name = 'patient_id') THEN
    EXECUTE 'create index if not exists idx_fk_ward_beds_patient_id on public.ward_beds (patient_id);';
  END IF;
END $migration$;
